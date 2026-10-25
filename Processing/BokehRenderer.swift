import CoreImage

/// 玉ボケと合成
struct BokehRenderer {
    /// 強さスライダーの値（0〜1）
    let strength: CGFloat
    var style = BlurStyle()

    /// mask = 1 の部分は元画像、0 の部分はぼかし画像。mask が nil ならフレーム全体をぼかす
    /// - Parameter time: フレームの時刻（フィルムの粒子用）
    func render(source: CIImage, mask: CIImage?, time: Double = 0) -> CIImage {
        var background = bokeh(source, radiusScale: 1)
        if style.isGradient, let mask {
            // 人の近くは弱いボケ、離れるほど強いボケになるよう2つを混ぜる
            let near = bokeh(source, radiusScale: Constants.gradientNearRadiusRatio)
            background = near.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: Self.proximity(of: mask),
            ])
        }
        background = style.preset.background(background)

        let composited = mask.map {
            source.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: $0,
            ])
        } ?? background
        return style.preset.finish(composited, time: time).cropped(to: source.extent)
    }

    func bokeh(_ image: CIImage, radiusScale: CGFloat) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        // 解像度が違っても見た目のボケ量が揃うよう、半径は長辺に比例させる
        let radius = strength * radiusScale * longSide * Constants.bokehRadiusRatio
        guard radius >= 0.5 else { return image }

        let workScale = min(1, Constants.bokehWorkingLongSide / longSide)
        let toWork = CGAffineTransform(scaleX: workScale, y: workScale)
        let workExtent = extent.applying(toWork)

        // 端が透けたり黒くならないよう、ぼかし前に clampedToExtent、ぼかし後に crop
        let blurred = image.clampedToExtent()
            .transformed(by: toWork)
            .applyingFilter("CIBokehBlur", parameters: [
                kCIInputRadiusKey: radius * workScale,
                "inputRingAmount": style.preset.ringAmount,
                "inputRingSize": Constants.bokehRingSize,
                "inputSoftness": style.preset.softness,
            ])
            .cropped(to: workExtent)

        guard workScale < 1 else { return blurred }
        return blurred.clampedToExtent()
            .transformed(by: toWork.inverted())
            .cropped(to: extent)
    }

    /// 人の近くほど 1、離れるほど 0 になる画像。マスクを大きくぼかして作る（重いので縮小して計算する）
    static func proximity(of mask: CIImage) -> CIImage {
        let extent = mask.extent
        let longSide = max(extent.width, extent.height)
        let scale = min(1, Constants.gradientWorkingLongSide / longSide)
        let toWork = CGAffineTransform(scaleX: scale, y: scale)
        let gain = Constants.gradientGain
        return mask.clampedToExtent()
            .transformed(by: toWork)
            .applyingGaussianBlur(sigma: Double(Constants.gradientWorkingLongSide * Constants.gradientFalloff))
            .transformed(by: toWork.inverted())
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
            ])
            .applyingFilter("CIColorClamp")
    }
}
