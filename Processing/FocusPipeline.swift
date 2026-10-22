import CoreImage
import CoreVideo

/// Vision 解析用のフレームを作る：表示の向きに回転し、長辺を縮小した BGRA
final class AnalysisFrameRenderer {
    let orientation: CGImagePropertyOrientation
    let size: CGSize
    private let pool: CVPixelBufferPool?

    init(sourceSize: CGSize, orientation: CGImagePropertyOrientation) {
        self.orientation = orientation
        let upright = CoordinateConverter.orientedSize(sourceSize, orientation)
        let scale = min(1, Constants.analysisLongSide / max(upright.width, upright.height))
        size = CGSize(width: (upright.width * scale).rounded(), height: (upright.height * scale).rounded())
        pool = PixelBufferFactory.makePool(width: Int(size.width), height: Int(size.height),
                                           format: kCVPixelFormatType_32BGRA)
    }

    func render(_ source: CIImage) -> CVPixelBuffer? {
        guard let pool, let buffer = PixelBufferFactory.make(from: pool) else { return nil }
        let upright = CoordinateConverter.reoriented(source, by: orientation)
        let scaled = upright.transformed(by: CGAffineTransform(scaleX: size.width / upright.extent.width,
                                                               y: size.height / upright.extent.height))
        RenderContext.shared.render(scaled, to: buffer, bounds: CGRect(origin: .zero, size: size),
                                    colorSpace: RenderContext.videoColorSpace)
        return buffer
    }
}

/// 1フレームごとの処理：追跡 → 対象マスク → 整形・平滑化 → 玉ボケ → 合成 → 顔の絵文字。
/// 見失ったときの猶予・全体ぼかし・復帰時のフェードインもここで扱う。
/// 書き出しキューからのみ使う（スレッドセーフではない）
final class FocusPipeline {
    private let orientation: CGImagePropertyOrientation
    private let initialFaceRect: CGRect
    private let analysis: AnalysisFrameRenderer
    private let maskProvider = PersonMaskProvider()
    private let renderer: BokehRenderer
    private let stickerTarget: StickerSettings.Target
    private let stickerRenderer: FaceStickerRenderer?
    private let stickerTracker = FaceStickerTracker()
    private var tracker: SubjectTracker?
    /// 最後に追跡できていた対象の顔
    private var lastTargetFace: CGRect?

    /// 対象（の顔またはマスク）が見つからなくなった時刻
    private var missingSince: Double?
    /// 猶予を過ぎてフレーム全体をぼかしている状態
    private var isFullyBlurred = false
    /// 復帰時のフェードイン開始時刻
    private var fadeInStart: Double?

    /// - Parameters:
    ///   - bufferSize: 回転前のピクセルバッファのサイズ
    ///   - orientation: 映像トラックの向き
    ///   - faceRect: 最初のフレーム（表示の向き）で選んだ顔の Vision 正規化座標
    init(bufferSize: CGSize, orientation: CGImagePropertyOrientation, faceRect: CGRect, strength: CGFloat,
         sticker: StickerSettings) {
        self.orientation = orientation
        self.initialFaceRect = faceRect
        analysis = AnalysisFrameRenderer(sourceSize: bufferSize, orientation: orientation)
        renderer = BokehRenderer(strength: strength)
        stickerTarget = sticker.target
        stickerRenderer = sticker.emoji.flatMap { FaceStickerRenderer(emoji: $0) }
    }

    /// - Returns: バッファの向き・解像度のままの出力画像
    func process(_ pixelBuffer: CVPixelBuffer, time: Double) -> CIImage {
        let source = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: RenderContext.videoColorSpace])
        guard let frame = analysis.render(source) else {
            let held = maskProvider.heldMask.map { PersonMaskProvider.fitted($0, to: source.extent, from: orientation) }
            return renderer.render(source: source, mask: held)
        }

        let targetFace = trackTarget(in: frame)
        let mask = analysisMask(in: frame, targetFace: targetFace, time: time)
            .map { PersonMaskProvider.fitted($0, to: source.extent, from: orientation) }
        let output = renderer.render(source: source, mask: mask)

        guard let stickerRenderer else { return output }
        return stickerRenderer.composite(faces: stickerFaces(in: frame, targetFace: targetFace),
                                         over: output, orientation: orientation)
    }

    /// 対象の顔の位置（Vision 正規化座標）。見失っていれば nil
    private func trackTarget(in frame: CVPixelBuffer) -> CGRect? {
        let face: CGRect?
        if let tracker {
            face = tracker.update(frame)
        } else {
            tracker = SubjectTracker(firstFrame: frame, faceRect: initialFaceRect)
            face = initialFaceRect
        }
        if let face { lastTargetFace = face }
        return face
    }

    /// 絵文字を貼る顔（Vision 正規化座標）
    private func stickerFaces(in frame: CVPixelBuffer, targetFace: CGRect?) -> [CGRect] {
        // 見失いの猶予中は直前の位置を対象の顔として扱う（一瞬で絵文字が外れて顔が出ないように）
        let target = targetFace ?? (isFullyBlurred ? nil : lastTargetFace)
        switch stickerTarget {
        case .subject:
            return target.map { [$0] } ?? []
        case .everyone:
            return stickerTracker.faces(in: frame)
        case .others:
            let faces = stickerTracker.faces(in: frame)
            guard let target,
                  let index = faces.indices.max(by: {
                      CoordinateConverter.iou(faces[$0], target) < CoordinateConverter.iou(faces[$1], target)
                  }),
                  CoordinateConverter.iou(faces[index], target) >= Constants.redetectMinIoU else {
                return faces
            }
            var others = faces
            others.remove(at: index)
            return others
        }
    }

    /// このフレームで使うマスク（解析解像度・表示の向き）。nil ならフレーム全体をぼかす
    private func analysisMask(in frame: CVPixelBuffer, targetFace: CGRect?, time: Double) -> CIImage? {
        if let targetFace, let raw = maskProvider.targetMask(in: frame, faceRect: targetFace) {
            if isFullyBlurred {
                isFullyBlurred = false
                fadeInStart = time
            }
            missingSince = nil
            return applyFadeIn(to: maskProvider.smoothed(raw), time: time)
        }

        // 見失い中
        let since = missingSince ?? time
        missingSince = since
        if !isFullyBlurred, time - since <= Constants.lostGraceDuration {
            // 一瞬の顔の向き変化や遮りでガタつかないよう、直前のマスクを使い続ける
            return maskProvider.heldMask
        }
        // 猶予を過ぎたら、対象がいない＝全部「それ以外」扱い
        isFullyBlurred = true
        fadeInStart = nil
        maskProvider.reset()
        return nil
    }

    /// 復帰時は reacquireFadeDuration 秒かけてマスクを濃くしていく
    private func applyFadeIn(to mask: CIImage, time: Double) -> CIImage {
        guard let start = fadeInStart else { return mask }
        let progress = CGFloat((time - start) / Constants.reacquireFadeDuration)
        if progress >= 1 {
            fadeInStart = nil
            return mask
        }
        let p = max(progress, 0)
        return mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: p, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: p, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: p, w: 0),
        ])
    }
}
