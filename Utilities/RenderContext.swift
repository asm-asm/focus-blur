import CoreImage
import CoreVideo
import Metal

/// アプリ全体で1つだけ使う CIContext（フレームごとに作らない）
enum RenderContext {
    static let shared: CIContext = {
        // 動画はフレームごとに入力が変わるので中間結果のキャッシュは不要（メモリ節約）
        let options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }()

    /// 動画フレームの読み込み・書き出しに使う色空間。入出力で同じものを使い、
    /// 対象人物のピクセルが往復で変わらないようにする
    static let videoColorSpace = CGColorSpace(name: CGColorSpace.itur_709)!
}

enum PixelBufferFactory {
    static func makePool(width: Int, height: Int, format: OSType) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        return pool
    }

    static func make(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
