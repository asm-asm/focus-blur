import CoreImage
import XCTest
@testable import FocusBlur

final class CoordinateConverterTests: XCTestCase {

    func testOrientationFromTransform() {
        // iPhone の縦向き撮影（1920x1080 のバッファを 90度回転して表示）
        let portrait = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        XCTAssertEqual(CoordinateConverter.orientation(for: portrait), .right)
        XCTAssertEqual(CoordinateConverter.orientation(for: .identity), .up)
        XCTAssertEqual(CoordinateConverter.orientation(for: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)), .down)
        XCTAssertEqual(CoordinateConverter.orientation(for: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)), .left)
    }

    func testInverseOrientation() {
        XCTAssertEqual(CoordinateConverter.inverse(of: .right), .left)
        XCTAssertEqual(CoordinateConverter.inverse(of: .left), .right)
        XCTAssertEqual(CoordinateConverter.inverse(of: .down), .down)
        XCTAssertEqual(CoordinateConverter.inverse(of: .up), .up)
    }

    func testOrientedSize() {
        let size = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(CoordinateConverter.orientedSize(size, .right), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(CoordinateConverter.orientedSize(size, .down), size)
    }

    func testReorientedRoundTripKeepsExtentAtOrigin() {
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let upright = CoordinateConverter.reoriented(image, by: .right)
        XCTAssertEqual(upright.extent, CGRect(x: 0, y: 0, width: 1080, height: 1920))
        let back = CoordinateConverter.reoriented(upright, by: CoordinateConverter.inverse(of: .right))
        XCTAssertEqual(back.extent, image.extent)
    }

    func testAspectFitRect() {
        let rect = CoordinateConverter.aspectFitRect(content: CGSize(width: 1000, height: 500),
                                                     in: CGSize(width: 300, height: 300))
        XCTAssertEqual(rect, CGRect(x: 0, y: 75, width: 300, height: 150))
    }

    func testViewPointToNormalizedFlipsY() {
        let imageRect = CGRect(x: 0, y: 75, width: 300, height: 150)
        let topLeft = CoordinateConverter.viewPointToNormalized(CGPoint(x: 0, y: 75), imageRect: imageRect)
        XCTAssertEqual(topLeft.x, 0, accuracy: 1e-9)
        XCTAssertEqual(topLeft.y, 1, accuracy: 1e-9)
        let center = CoordinateConverter.viewPointToNormalized(CGPoint(x: 150, y: 150), imageRect: imageRect)
        XCTAssertEqual(center.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(center.y, 0.5, accuracy: 1e-9)
    }

    func testNormalizedRectToView() {
        let imageRect = CGRect(x: 0, y: 75, width: 300, height: 150)
        // 正規化座標で上半分の左側（Vision は左下原点なので y = 0.5〜1）
        let rect = CoordinateConverter.normalizedRectToView(CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                                                           imageRect: imageRect)
        XCTAssertEqual(rect, CGRect(x: 0, y: 75, width: 150, height: 75))
    }

    func testIoU() {
        let a = CGRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertEqual(CoordinateConverter.iou(a, a), 1, accuracy: 1e-9)
        XCTAssertEqual(CoordinateConverter.iou(a, CGRect(x: 2, y: 2, width: 1, height: 1)), 0)
        XCTAssertEqual(CoordinateConverter.iou(a, CGRect(x: 0.5, y: 0, width: 1, height: 1)), 1.0 / 3.0, accuracy: 1e-9)
    }
}
