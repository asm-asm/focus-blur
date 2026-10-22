import CoreGraphics
import CoreVideo
import Vision

/// 対象人物の顔を追跡する。見失いの判定と、特徴量による再認識も行う。
///
/// 入力フレームは表示の向きに回転済みの解析用フレーム（`AnalysisFrameRenderer`）。
/// 返す矩形はそのフレームでの Vision 正規化座標。
final class SubjectTracker {
    private var sequenceHandler = VNSequenceRequestHandler()
    private var trackRequest: VNTrackObjectRequest
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let printRequest: VNGenerateImageFeaturePrintRequest
    private var referencePrint: VNFeaturePrintObservation?
    private var frameIndex = 0
    private(set) var isLost = false

    /// - Parameters:
    ///   - firstFrame: 対象を選んだフレーム
    ///   - faceRect: 選んだ顔の矩形（Vision 正規化座標）
    init(firstFrame: CVPixelBuffer, faceRect: CGRect) {
        printRequest = VNGenerateImageFeaturePrintRequest()
        printRequest.revision = VNGenerateImageFeaturePrintRequestRevision2
        printRequest.imageCropAndScaleOption = .scaleFit
        trackRequest = Self.makeTrackRequest(for: faceRect)
        // 再認識用に、選んだ顔の特徴量を保存しておく（取れなければ再認識なしで動く）
        referencePrint = featurePrint(of: faceRect, in: firstFrame)
    }

    /// 次のフレームで対象の顔を探す。見失っている間は nil
    func update(_ frame: CVPixelBuffer) -> CGRect? {
        frameIndex += 1
        if isLost {
            return reacquire(in: frame)
        }
        guard let tracked = track(frame) else {
            isLost = true
            return nil
        }
        if frameIndex % Constants.redetectInterval == 0 {
            return corrected(tracked, in: frame)
        }
        return tracked
    }

    // MARK: 追跡

    private func track(_ frame: CVPixelBuffer) -> CGRect? {
        do {
            try sequenceHandler.perform([trackRequest], on: frame)
        } catch {
            return nil
        }
        guard let observation = trackRequest.results?.first as? VNDetectedObjectObservation,
              observation.confidence >= Constants.trackingConfidenceThreshold else {
            return nil
        }
        trackRequest.inputObservation = observation
        return observation.boundingBox
    }

    /// 顔検出をやり直し、追跡中の矩形と最も重なる顔で追跡を補正する
    private func corrected(_ tracked: CGRect, in frame: CVPixelBuffer) -> CGRect {
        let faces = detectFaces(in: frame)
        guard let best = faces.max(by: { CoordinateConverter.iou($0, tracked) < CoordinateConverter.iou($1, tracked) }),
              CoordinateConverter.iou(best, tracked) >= Constants.redetectMinIoU else {
            return tracked
        }
        // すれ違いざまに隣の人へ乗り移らないよう、明らかに別人の顔では補正しない
        if referencePrint != nil, let d = distance(to: best, in: frame),
           d > Constants.identitySwitchDistance {
            return tracked
        }
        reseed(with: best)
        return best
    }

    /// 見失い中：検出した顔の中から保存済み特徴量に近い顔を探し、見つかれば追跡を再開する
    private func reacquire(in frame: CVPixelBuffer) -> CGRect? {
        guard referencePrint != nil else { return nil }
        let candidates = detectFaces(in: frame)
            .sorted { $0.width * $0.height > $1.width * $1.height }
            .prefix(Constants.reidentifyMaxCandidates)
        let scored = candidates.compactMap { face in distance(to: face, in: frame).map { (face, $0) } }
        guard let best = scored.min(by: { $0.1 < $1.1 }),
              best.1 <= Constants.reidentifyDistanceThreshold else {
            return nil
        }
        reseed(with: best.0)
        isLost = false
        return best.0
    }

    /// 追跡を新しい矩形でやり直す。ハンドラも作り直して古いトラッカーを確実に解放する
    private func reseed(with rect: CGRect) {
        sequenceHandler = VNSequenceRequestHandler()
        trackRequest = Self.makeTrackRequest(for: rect)
    }

    private static func makeTrackRequest(for rect: CGRect) -> VNTrackObjectRequest {
        let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: rect))
        request.trackingLevel = .accurate
        return request
    }

    // MARK: 顔検出・特徴量

    private func detectFaces(in frame: CVPixelBuffer) -> [CGRect] {
        let handler = VNImageRequestHandler(cvPixelBuffer: frame)
        do {
            try handler.perform([faceRequest])
        } catch {
            return []
        }
        return faceRequest.results?.map(\.boundingBox) ?? []
    }

    private func featurePrint(of faceRect: CGRect, in frame: CVPixelBuffer) -> VNFeaturePrintObservation? {
        let padded = faceRect
            .insetBy(dx: -faceRect.width * Constants.faceCropPadding, dy: -faceRect.height * Constants.faceCropPadding)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !padded.isNull, padded.width > 0, padded.height > 0 else { return nil }
        printRequest.regionOfInterest = padded
        let handler = VNImageRequestHandler(cvPixelBuffer: frame)
        do {
            try handler.perform([printRequest])
        } catch {
            return nil
        }
        return printRequest.results?.first
    }

    private func distance(to faceRect: CGRect, in frame: CVPixelBuffer) -> Float? {
        guard let referencePrint, let candidate = featurePrint(of: faceRect, in: frame) else { return nil }
        var value: Float = 0
        do {
            try referencePrint.computeDistance(&value, to: candidate)
        } catch {
            return nil
        }
        return value
    }

    // MARK: 対象選択画面用

    /// 静止画の顔検出（Vision 正規化座標）
    static func detectFaces(in image: CGImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return request.results?.map(\.boundingBox) ?? []
    }
}
