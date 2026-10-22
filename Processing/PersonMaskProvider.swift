import CoreImage
import CoreVideo
import Vision

/// 人物インスタンスマスクから対象人物のマスクだけを取り出し、整形・平滑化する
final class PersonMaskProvider {
    private let request = VNGeneratePersonInstanceMaskRequest()
    private var smoothingPool: CVPixelBufferPool?
    private var smoothingSize: CGSize = .zero
    /// 前フレームまでで平滑化したマスク（解析解像度・表示の向き）
    private(set) var heldMask: CIImage?

    /// 対象人物のマスク（解析フレームと同じ解像度・向き、0〜1）。人物が見つからなければ nil
    func targetMask(in frame: CVPixelBuffer, faceRect: CGRect) -> CIImage? {
        let handler = VNImageRequestHandler(cvPixelBuffer: frame)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  let instance = Self.instance(in: observation, matching: faceRect) else {
                return nil
            }
            let mask = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instance),
                                                                  from: handler)
            return CIImage(cvPixelBuffer: mask, options: [.colorSpace: NSNull()])
        } catch {
            return nil
        }
    }

    /// 顔の中心を含むインスタンス。なければ顔矩形と最も重なるインスタンス
    static func instance(in observation: VNInstanceMaskObservation, matching faceRect: CGRect) -> Int? {
        let labels = observation.instanceMask
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(labels) else { return nil }
        let width = CVPixelBufferGetWidth(labels)
        let height = CVPixelBufferGetHeight(labels)
        let rowBytes = CVPixelBufferGetBytesPerRow(labels)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        // Vision 座標は左下原点、ラベル画像は上の行から並んでいる
        func column(_ x: CGFloat) -> Int { min(max(Int(x * CGFloat(width)), 0), width - 1) }
        func row(_ y: CGFloat) -> Int { min(max(Int((1 - y) * CGFloat(height)), 0), height - 1) }

        let center = Int(pixels[row(faceRect.midY) * rowBytes + column(faceRect.midX)])
        if center != 0, observation.allInstances.contains(center) {
            return center
        }

        var counts: [Int: Int] = [:]
        for y in row(faceRect.maxY)...row(faceRect.minY) {
            for x in column(faceRect.minX)...column(faceRect.maxX) {
                let label = Int(pixels[y * rowBytes + x])
                if label != 0 { counts[label, default: 0] += 1 }
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    /// ちらつき防止：前フレームのマスクと加重平均する（今回 0.7 ＋ 前回 0.3）。
    /// 結果はピクセルバッファに描き出しておき、CIImage のグラフがフレームごとに伸びていかないようにする
    func smoothed(_ mask: CIImage) -> CIImage {
        let extent = mask.extent
        var blended = mask
        if let heldMask, heldMask.extent == extent {
            // CIDissolveTransition: input × (1 − time) + target × time
            blended = mask.applyingFilter("CIDissolveTransition", parameters: [
                kCIInputTargetImageKey: heldMask,
                kCIInputTimeKey: 1 - Constants.maskCurrentWeight,
            ])
        }
        if smoothingPool == nil || smoothingSize != extent.size {
            smoothingPool = PixelBufferFactory.makePool(width: Int(extent.width), height: Int(extent.height),
                                                        format: kCVPixelFormatType_OneComponent8)
            smoothingSize = extent.size
        }
        guard let smoothingPool, let buffer = PixelBufferFactory.make(from: smoothingPool) else {
            return blended
        }
        RenderContext.shared.render(blended, to: buffer, bounds: extent, colorSpace: nil)
        let stored = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        heldMask = stored
        return stored
    }

    /// 平滑化の履歴を捨てる（長く見失ったとき）
    func reset() {
        heldMask = nil
    }

    /// 解析用マスク（表示の向き・縮小）を元フレームの向き・解像度に合わせ、境界をフェザーする
    /// - Parameters:
    ///   - orientation: 解析フレームを作るときに適用した向き
    ///   - extent: 元フレームの extent
    static func fitted(_ mask: CIImage, to extent: CGRect, from orientation: CGImagePropertyOrientation) -> CIImage {
        let rotated = CoordinateConverter.reoriented(mask, by: CoordinateConverter.inverse(of: orientation))
        let scaled = rotated.transformed(by: CGAffineTransform(scaleX: extent.width / rotated.extent.width,
                                                               y: extent.height / rotated.extent.height))
        let radius = max(extent.width, extent.height) * Constants.maskFeatherRatio
        return scaled.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius))
            .cropped(to: extent)
    }
}
