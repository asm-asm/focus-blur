import CoreImage

/// 玉ボケと合成
struct BokehRenderer {
    /// 強さスライダーの値（0〜1）
    let strength: CGFloat

    /// mask = 1 の部分は元画像、0 の部分はぼかし画像。mask が nil ならフレーム全体をぼかす
    func render(source: CIImage, mask: CIImage?) -> CIImage {
        let blurred = bokeh(source)
        guard let mask else { return blurred }
        return source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: mask,
        ])
    }

    func bokeh(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        // 解像度が違っても見た目のボケ量が揃うよう、半径は長辺に比例させる
        let radius = strength * longSide * Constants.bokehRadiusRatio
        guard radius >= 0.5 else { return image }

        let workScale = min(1, Constants.bokehWorkingLongSide / longSide)
        let toWork = CGAffineTransform(scaleX: workScale, y: workScale)
        let workExtent = extent.applying(toWork)

        // 端が透けたり黒くならないよう、ぼかし前に clampedToExtent、ぼかし後に crop
        let blurred = image.clampedToExtent()
            .transformed(by: toWork)
            .applyingFilter("CIBokehBlur", parameters: [
                kCIInputRadiusKey: radius * workScale,
                "inputRingAmount": Constants.bokehRingAmount,
                "inputRingSize": Constants.bokehRingSize,
                "inputSoftness": Constants.bokehSoftness,
            ])
            .cropped(to: workExtent)

        guard workScale < 1 else { return blurred }
        return blurred.clampedToExtent()
            .transformed(by: toWork.inverted())
            .cropped(to: extent)
    }
}
