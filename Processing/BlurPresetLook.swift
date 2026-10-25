import CoreImage

/// プリセットごとの Core Image の処理
extension BlurPreset {
    var ringAmount: CGFloat {
        switch self {
        case .dreamy: return 0.25
        default: return Constants.bokehRingAmount
        }
    }

    var softness: CGFloat {
        switch self {
        case .dreamy: return 0.6
        default: return Constants.bokehSoftness
        }
    }

    /// ぼかした背景だけにかける処理
    func background(_ image: CIImage) -> CIImage {
        switch self {
        case .natural, .film:
            return image
        case .dreamy:
            return image
                .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 0.35])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.9])
        case .monoBackground:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1.05,
            ])
        }
    }

    /// 合成後のフレーム全体にかける処理
    /// - Parameter time: フィルムの粒子をフレームごとに変えるための時刻（秒）
    func finish(_ image: CIImage, time: Double) -> CIImage {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        switch self {
        case .natural, .monoBackground:
            return image
        case .film:
            let toned = image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.85,
                    kCIInputContrastKey: 0.95,
                ])
                // 黒を少し持ち上げ（色あせ）、暖色に寄せる
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0.96, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.95, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.9, w: 0),
                    "inputBiasVector": CIVector(x: 0.04, y: 0.025, z: 0.01, w: 0),
                ])
                .applyingFilter("CIVignetteEffect", parameters: [
                    kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
                    kCIInputRadiusKey: longSide * 0.6,
                    kCIInputIntensityKey: 0.45,
                ])
            return Self.addGrain(to: toned, time: time).cropped(to: extent)
        case .dreamy:
            return image.clampedToExtent()
                .applyingFilter("CIBloom", parameters: [
                    kCIInputRadiusKey: longSide * 0.012,
                    kCIInputIntensityKey: 0.5,
                ])
                .cropped(to: extent)
        }
    }

    /// フィルムの粒子。フレームごとに模様をずらし、解像度が高いほど粒を大きくする
    private static func addGrain(to image: CIImage, time: Double) -> CIImage {
        let extent = image.extent
        let grainScale = max(1, max(extent.width, extent.height) / 1400)
        let seed = (time * 7919).truncatingRemainder(dividingBy: 997)
        let amount = Constants.filmGrainAmount
        let grain = CIFilter(name: "CIRandomGenerator")!.outputImage!
            .transformed(by: CGAffineTransform(translationX: seed * 13, y: seed * 29))
            .transformed(by: CGAffineTransform(scaleX: grainScale, y: grainScale))
            // 白黒にして、0.5 を中心に振れ幅を小さくする（ソフトライトで 0.5 は変化なし）
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: amount, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.5 * (1 - amount), y: 0.5 * (1 - amount), z: 0.5 * (1 - amount), w: 1),
            ])
            .cropped(to: extent)
        return grain.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }
}
