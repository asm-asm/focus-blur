import CoreGraphics
import CoreVideo
import Vision

/// 絵文字を貼る頭の位置を毎フレーム求め、前フレームと対応づけて追う。
///
/// - 顔検出に加えて体の姿勢（鼻・目・耳・首・肩）から頭の位置を推定し、横顔・下向き・後ろ向きでも外れにくくする
/// - 動きの向きと速さから位置を予測し、絵文字が遅れてずれないようにする
/// - 検出が途切れても少しの間は予測位置に残し、少し大きくして素顔が出ないようにする
final class FaceStickerTracker {
    struct Face: Equatable {
        let id: Int
        /// Vision 正規化座標
        let rect: CGRect
    }

    private struct Track {
        let id: Int
        /// 最後に検出できたときの位置
        var rect: CGRect
        /// 中心の移動速度（正規化座標 / 秒）
        var velocity: CGVector
        var lastSeen: Double
    }

    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var tracks: [Track] = []
    private var nextID = 0

    /// - Parameters:
    ///   - faceFrame: 顔検出用の解析フレーム（小さい顔も拾えるよう高めの解像度）
    ///   - poseFrame: 姿勢推定用の解析フレーム（faceFrame と同じ向き・画角）
    func faces(faceFrame: CVPixelBuffer, poseFrame: CVPixelBuffer, time: Double) -> [Face] {
        let faces = Self.run(faceRequest, on: VNImageRequestHandler(cvPixelBuffer: faceFrame))
            ? faceRequest.results?.map(\.boundingBox) ?? []
            : []
        let poseSize = CGSize(width: CVPixelBufferGetWidth(poseFrame), height: CVPixelBufferGetHeight(poseFrame))
        let heads = Self.run(poseRequest, on: VNImageRequestHandler(cvPixelBuffer: poseFrame))
            ? Self.headRects(from: poseRequest.results ?? [], frameSize: poseSize)
            : []
        return update(detections: Self.merge(faces: faces, heads: heads), time: time)
    }

    /// 静止画（調整画面のプレビュー用）から顔と頭の位置を求める
    static func detect(in image: CGImage) -> [CGRect] {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let poseRequest = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let faces = run(faceRequest, on: handler) ? faceRequest.results?.map(\.boundingBox) ?? [] : []
        let heads = run(poseRequest, on: handler)
            ? headRects(from: poseRequest.results ?? [], frameSize: CGSize(width: image.width, height: image.height))
            : []
        return merge(faces: faces, heads: heads)
    }

    // MARK: 追跡

    /// 検出結果で追跡中の顔を更新し、このフレームで絵文字を貼る位置を返す
    func update(detections: [CGRect], time: Double) -> [Face] {
        var unmatched = detections
        for index in tracks.indices {
            let predicted = predictedRect(of: tracks[index], at: time)
            guard let best = unmatched.indices.min(by: {
                CoordinateConverter.centerDistance(unmatched[$0], predicted)
                    < CoordinateConverter.centerDistance(unmatched[$1], predicted)
            }), CoordinateConverter.centerDistance(unmatched[best], predicted) <= Constants.stickerMatchMaxDistance else {
                continue
            }
            let detection = unmatched.remove(at: best)
            let dt = time - tracks[index].lastSeen
            if dt > 0 {
                let measured = CGVector(dx: (detection.midX - tracks[index].rect.midX) / dt,
                                        dy: (detection.midY - tracks[index].rect.midY) / dt)
                tracks[index].velocity = Self.mix(tracks[index].velocity, measured, weight: Constants.stickerVelocitySmoothing)
            }
            tracks[index].rect = Self.blend(predicted, detection, weight: Constants.stickerSmoothing)
            tracks[index].lastSeen = time
        }
        tracks.removeAll { time - $0.lastSeen > Constants.stickerHoldDuration }
        for detection in unmatched {
            tracks.append(Track(id: nextID, rect: detection, velocity: .zero, lastSeen: time))
            nextID += 1
        }
        return tracks.map { track in
            var rect = predictedRect(of: track, at: time)
            if track.lastSeen < time {
                // 見失い中は位置が不確かなので大きめに覆う
                let grow = (Constants.stickerMissingGrowth - 1) / 2
                rect = rect.insetBy(dx: -rect.width * grow, dy: -rect.height * grow)
            }
            return Face(id: track.id, rect: rect)
        }
    }

    private func predictedRect(of track: Track, at time: Double) -> CGRect {
        let dt = min(time - track.lastSeen, Constants.stickerHoldDuration)
        guard dt > 0 else { return track.rect }
        return track.rect.offsetBy(dx: track.velocity.dx * dt, dy: track.velocity.dy * dt)
    }

    // MARK: 検出

    private static func run(_ request: VNRequest, on handler: VNImageRequestHandler) -> Bool {
        do {
            try handler.perform([request])
            return true
        } catch {
            return false
        }
    }

    /// 体の姿勢から頭の位置を推定する。大きさは顔検出の矩形と同じくらいになるよう合わせる
    static func headRects(from observations: [VNHumanBodyPoseObservation], frameSize: CGSize) -> [CGRect] {
        observations.compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            func point(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                guard let p = points[name], p.confidence >= Constants.poseMinConfidence else { return nil }
                return CGPoint(x: p.location.x * frameSize.width, y: p.location.y * frameSize.height)
            }
            func distance(_ a: CGPoint?, _ b: CGPoint?) -> CGFloat? {
                guard let a, let b else { return nil }
                return hypot(a.x - b.x, a.y - b.y)
            }

            let headPoints = [VNHumanBodyPoseObservation.JointName.nose, .leftEye, .rightEye, .leftEar, .rightEar]
                .compactMap(point)
            guard !headPoints.isEmpty else { return nil }
            let center = CGPoint(x: headPoints.map(\.x).reduce(0, +) / CGFloat(headPoints.count),
                                 y: headPoints.map(\.y).reduce(0, +) / CGFloat(headPoints.count))

            // 見えている部位ごとの推定のうち、いちばん大きいものを使う（隠し漏れを防ぐ）
            let estimates: [CGFloat] = [
                distance(point(.leftEar), point(.rightEar)).map { $0 * 1.1 },
                distance(point(.leftEye), point(.rightEye)).map { $0 * 2.4 },
                distance(point(.neck), center).map { $0 * 1.3 },
                distance(point(.leftShoulder), point(.rightShoulder)).map { $0 * 0.5 },
            ].compactMap { $0 }
            guard let side = estimates.max(), side > 0 else { return nil }

            return CGRect(x: (center.x - side / 2) / frameSize.width, y: (center.y - side / 2) / frameSize.height,
                          width: side / frameSize.width, height: side / frameSize.height)
        }
    }

    /// 顔検出と姿勢の推定を合わせる。同じ人の頭は位置が正確な顔検出を優先する
    static func merge(faces: [CGRect], heads: [CGRect]) -> [CGRect] {
        faces + heads.filter { head in
            !faces.contains { CoordinateConverter.centerDistance($0, head) <= Constants.stickerMatchMaxDistance }
        }
    }

    // MARK: 補間

    /// a × (1 − weight) + b × weight
    private static func blend(_ a: CGRect, _ b: CGRect, weight: CGFloat) -> CGRect {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * weight }
        return CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY),
                      width: mix(a.width, b.width), height: mix(a.height, b.height))
    }

    private static func mix(_ a: CGVector, _ b: CGVector, weight: CGFloat) -> CGVector {
        CGVector(dx: a.dx + (b.dx - a.dx) * weight, dy: a.dy + (b.dy - a.dy) * weight)
    }
}
