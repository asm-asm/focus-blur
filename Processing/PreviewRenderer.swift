import CoreGraphics
import CoreImage

/// 調整画面のプレビュー：最初のフレームを縮小し、マスクは一度だけ作って使い回す
actor PreviewRenderer {
    private let source: CIImage
    private let mask: CIImage?
    nonisolated let hasMask: Bool

    /// - Parameters:
    ///   - firstFrame: 表示の向きの最初のフレーム
    ///   - faceRect: 選んだ顔（Vision 正規化座標）
    init(firstFrame: CGImage, faceRect: CGRect) {
        let full = CIImage(cgImage: firstFrame)
        let scale = min(1, Constants.previewLongSide / max(full.extent.width, full.extent.height))
        let image = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        source = image

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

    func render(strength: Double) -> CGImage? {
        let output = BokehRenderer(strength: CGFloat(strength)).render(source: source, mask: mask)
        return RenderContext.shared.createCGImage(output, from: source.extent)
    }
}
