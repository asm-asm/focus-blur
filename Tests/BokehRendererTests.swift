import CoreImage
import XCTest
@testable import FocusBlur

final class BokehRendererTests: XCTestCase {
    private let source = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.4))
        .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
    /// 左半分が人物
    private let mask = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 48, height: 64))
        .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64)))

    func testEveryStyleRendersAtSourceExtent() throws {
        for preset in BlurPreset.allCases {
            for isGradient in [false, true] {
                let renderer = BokehRenderer(strength: 0.8, style: BlurStyle(preset: preset, isGradient: isGradient))
                for mask in [mask, nil] {
                    let output = renderer.render(source: source, mask: mask, time: 1.5)
                    XCTAssertEqual(output.extent, source.extent, "\(preset) gradient=\(isGradient)")
                    // フィルター名やパラメータを間違えると描画できないので、実際に描画して確かめる
                    let image = try XCTUnwrap(RenderContext.shared.createCGImage(output, from: output.extent),
                                              "\(preset) gradient=\(isGradient)")
                    XCTAssertEqual(image.width, 96)
                }
            }
        }
    }

    func testProximityIsHighNearPersonAndLowFarAway() throws {
        let wide = CGRect(x: 0, y: 0, width: 1000, height: 100)
        let person = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
            .composited(over: CIImage(color: .black).cropped(to: wide))
        let proximity = BokehRenderer.proximity(of: person)
        XCTAssertGreaterThan(try red(of: proximity, at: CGPoint(x: 110, y: 50)), 0.9)
        XCTAssertLessThan(try red(of: proximity, at: CGPoint(x: 990, y: 50)), 0.1)
    }

    private func red(of image: CIImage, at point: CGPoint) throws -> CGFloat {
        var pixel = [UInt8](repeating: 0, count: 4)
        RenderContext.shared.render(image, toBitmap: &pixel, rowBytes: 4,
                                    bounds: CGRect(x: point.x, y: point.y, width: 1, height: 1),
                                    format: .RGBA8, colorSpace: nil)
        return CGFloat(pixel[0]) / 255
    }
}
