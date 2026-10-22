import CoreImage
import UIKit

/// 顔の位置に絵文字を重ねる
struct FaceStickerRenderer {
    private let sticker: CIImage

    init?(emoji: String) {
        let side = Constants.stickerImageSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: side * 0.8)])
            let size = text.size()
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        }
        guard let cgImage = image.cgImage else { return nil }
        sticker = CIImage(cgImage: cgImage)
    }

    /// 顔ごとに絵文字を並べた透明なレイヤー（表示の向き）。extent はキャンバスと一致する
    /// - Parameter faces: Vision 正規化座標の顔矩形
    func layer(for faces: [CGRect], canvasSize: CGSize) -> CIImage {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        var result = CIImage(color: .clear).cropped(to: canvas)
        for face in faces {
            let rect = CGRect(x: face.minX * canvasSize.width, y: face.minY * canvasSize.height,
                              width: face.width * canvasSize.width, height: face.height * canvasSize.height)
            let side = max(rect.width, rect.height) * Constants.stickerScale
            let scale = side / sticker.extent.width
            let placed = sticker
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2))
            result = placed.composited(over: result)
        }
        return result.cropped(to: canvas)
    }

    /// 出力画像（orientation で回転する前の向き）に絵文字を重ねる
    func composite(faces: [CGRect], over output: CIImage, orientation: CGImagePropertyOrientation) -> CIImage {
        guard !faces.isEmpty else { return output }
        let uprightSize = CoordinateConverter.orientedSize(output.extent.size, orientation)
        let upright = layer(for: faces, canvasSize: uprightSize)
        let layer = CoordinateConverter.reoriented(upright, by: CoordinateConverter.inverse(of: orientation))
        return layer.composited(over: output)
    }
}
