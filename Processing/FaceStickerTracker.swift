import CoreGraphics
import CoreVideo
import Vision

/// 絵文字を貼る顔を毎フレーム検出し、前フレームと対応づけて位置のガタつきと一瞬の検出漏れを抑える
final class FaceStickerTracker {
    private struct Track {
        var rect: CGRect
        var missingFrames: Int
    }

    private let request = VNDetectFaceRectanglesRequest()
    private var tracks: [Track] = []

    /// 解析フレームから顔を検出し、貼る位置（Vision 正規化座標）を返す
    func faces(in frame: CVPixelBuffer) -> [CGRect] {
        let handler = VNImageRequestHandler(cvPixelBuffer: frame)
        let detections: [CGRect]
        do {
            try handler.perform([request])
            detections = request.results?.map(\.boundingBox) ?? []
        } catch {
            detections = []
        }
        return update(detections: detections)
    }

    /// 検出結果で追跡中の顔を更新する
    func update(detections: [CGRect]) -> [CGRect] {
        var unmatched = detections
        for index in tracks.indices {
            let rect = tracks[index].rect
            if let best = unmatched.indices.max(by: {
                CoordinateConverter.iou(unmatched[$0], rect) < CoordinateConverter.iou(unmatched[$1], rect)
            }), CoordinateConverter.iou(unmatched[best], rect) >= Constants.stickerMatchMinIoU {
                tracks[index].rect = Self.blend(rect, unmatched[best], weight: Constants.stickerSmoothing)
                tracks[index].missingFrames = 0
                unmatched.remove(at: best)
            } else {
                // 検出漏れ：数フレームは直前の位置に残す
                tracks[index].missingFrames += 1
            }
        }
        tracks.removeAll { $0.missingFrames > Constants.stickerHoldFrames }
        tracks += unmatched.map { Track(rect: $0, missingFrames: 0) }
        return tracks.map(\.rect)
    }

    /// old × (1 − weight) + new × weight
    private static func blend(_ old: CGRect, _ new: CGRect, weight: CGFloat) -> CGRect {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * weight }
        return CGRect(x: mix(old.minX, new.minX), y: mix(old.minY, new.minY),
                      width: mix(old.width, new.width), height: mix(old.height, new.height))
    }
}
