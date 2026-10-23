import CoreGraphics
import CoreImage

/// 調整画面のプレビュー：最初のフレームを縮小し、マスクは一度だけ作って使い回す
actor PreviewRenderer {
    private let source: CIImage
    private let mask: CIImage?
    private let targetFace: CGRect
    private let faces: [CGRect]
    nonisolated let hasMask: Bool

    /// - Parameters:
    ///   - firstFrame: 表示の向きの最初のフレーム
    ///   - faceRect: 選んだ顔（Vision 正規化座標）
    init(firstFrame: CGImage, faceRect: CGRect) {
        let full = CIImage(cgImage: firstFrame)
        let scale = min(1, Constants.previewLongSide / max(full.extent.width, full.extent.height))
        let image = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        source = image
        targetFace = faceRect
        // 書き出しと同じく、顔検出と体の姿勢から頭の位置を求める
        faces = FaceStickerTracker.detect(in: firstFrame)

        // 書き出しと同じ解析経路（長辺 analysisLongSide に縮小）でマスクを作る
        let analysis = AnalysisFrameRenderer(sourceSize: image.extent.size, orientation: .up)
        let provider = PersonMaskProvider()
        if let frame = analysis.render(image), let raw = provider.targetMask(in: frame, faceRect: faceRect) {
            mask = PersonMaskProvider.fitted(raw, to: image.extent, from: .up)
        } else {
            mask = nil
        }
        hasMask = mask != nil
    }

    func render(strength: Double, sticker: StickerSettings) -> CGImage? {
        var output = BokehRenderer(strength: CGFloat(strength)).render(source: source, mask: mask)
        if let emoji = sticker.emoji, let stickerRenderer = FaceStickerRenderer(emoji: emoji) {
            output = stickerRenderer.composite(faces: stickerFaces(for: sticker.target), over: output, orientation: .up)
        }
        return RenderContext.shared.createCGImage(output, from: source.extent)
    }

    private func stickerFaces(for target: StickerSettings.Target) -> [CGRect] {
        switch target {
        case .subject:
            return [targetFace]
        case .others:
            guard let target = targetIndex else { return faces }
            return faces.indices.filter { $0 != target }.map { faces[$0] }
        case .everyone:
            return targetIndex == nil ? faces + [targetFace] : faces
        }
    }

    /// faces のうち、選んだ顔に当たるもの
    private var targetIndex: Int? {
        guard let best = faces.indices.min(by: {
            CoordinateConverter.centerDistance(faces[$0], targetFace) < CoordinateConverter.centerDistance(faces[$1], targetFace)
        }), CoordinateConverter.centerDistance(faces[best], targetFace) <= Constants.stickerMatchMaxDistance else {
            return nil
        }
        return best
    }
}
