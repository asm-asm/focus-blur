import CoreGraphics
import CoreImage
import ImageIO

/// 座標系の変換
///
/// - 表示座標: SwiftUI のビュー座標（左上原点・y下向き）
/// - 画像座標: 表示の向き（preferredTransform 適用後）の画像
/// - Vision 正規化座標: 0〜1・左下原点（Core Image と同じ向き）
/// - バッファ座標: 回転前のピクセルバッファ（AVAssetReader から出てくる向き）
///
/// Vision の解析は「表示の向き」に回転した画像で行う（顔検出は正立した顔を前提にしているため）。
/// タップ座標・顔矩形・マスクはすべて表示の向きで扱い、合成の直前にマスクだけを
/// `reoriented(_:by: inverse(of:))` でバッファの向きに戻す。
enum CoordinateConverter {

    // MARK: 向き

    /// 映像トラックの preferredTransform に対応する EXIF の向き
    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a.rounded(), t.b.rounded(), t.c.rounded(), t.d.rounded()) {
        case (1, 0, 0, 1): return .up
        case (-1, 0, 0, -1): return .down
        case (0, 1, -1, 0): return .right   // iPhone の縦向き撮影
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, 1): return .upMirrored
        case (1, 0, 0, -1): return .downMirrored
        case (0, 1, 1, 0): return .leftMirrored
        case (0, -1, -1, 0): return .rightMirrored
        default: return .up
        }
    }

    /// 回転を元に戻す向き
    static func inverse(of orientation: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .right: return .left
        case .left: return .right
        default: return orientation  // 180度回転・各ミラーは自分自身が逆
        }
    }

    /// 向きを適用した後のサイズ
    static func orientedSize(_ size: CGSize, _ orientation: CGImagePropertyOrientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: size.height, height: size.width)
        default:
            return size
        }
    }

    /// 向きを適用し、extent の原点を (0, 0) に揃えた画像
    static func reoriented(_ image: CIImage, by orientation: CGImagePropertyOrientation) -> CIImage {
        let rotated = image.oriented(orientation)
        return rotated.transformed(by: CGAffineTransform(translationX: -rotated.extent.minX,
                                                         y: -rotated.extent.minY))
    }

    // MARK: 表示座標 ⇔ Vision 正規化座標

    /// `scaledToFit` で表示したときに画像が占める矩形
    static func aspectFitRect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return .zero }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// 表示座標の点 → Vision 正規化座標（左下原点）
    static func viewPointToNormalized(_ point: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(x: (point.x - imageRect.minX) / imageRect.width,
                y: 1 - (point.y - imageRect.minY) / imageRect.height)
    }

    /// Vision 正規化座標の矩形 → 表示座標の矩形
    static func normalizedRectToView(_ rect: CGRect, imageRect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + rect.minX * imageRect.width,
               y: imageRect.minY + (1 - rect.maxY) * imageRect.height,
               width: rect.width * imageRect.width,
               height: rect.height * imageRect.height)
    }

    // MARK: 矩形

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let inter = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? inter / union : 0
    }
}
