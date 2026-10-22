import CoreImage
import XCTest
@testable import FocusBlur

final class FaceStickerTests: XCTestCase {

    func testTrackerSmoothsMatchedFace() {
        let tracker = FaceStickerTracker()
        let first = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        XCTAssertEqual(tracker.update(detections: [first]), [first])

        let moved = first.offsetBy(dx: 0.05, dy: 0)
        let faces = tracker.update(detections: [moved])
        XCTAssertEqual(faces.count, 1)
        // 新しい位置へ stickerSmoothing の割合だけ近づく
        XCTAssertEqual(faces[0].minX, 0.4 + 0.05 * Constants.stickerSmoothing, accuracy: 1e-9)
    }

    func testTrackerHoldsMissingFaceForAFewFrames() {
        let tracker = FaceStickerTracker()
        let face = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        _ = tracker.update(detections: [face])
        for _ in 0..<Constants.stickerHoldFrames {
            XCTAssertEqual(tracker.update(detections: []), [face])
        }
        XCTAssertEqual(tracker.update(detections: []), [])
    }

    func testTrackerAddsNewFaces() {
        let tracker = FaceStickerTracker()
        let a = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2)
        _ = tracker.update(detections: [a])
        XCTAssertEqual(Set(tracker.update(detections: [a, b]).map(\.minX)), [a.minX, b.minX])
    }

    func testStickerLayerMatchesOutputExtent() throws {
        let renderer = try XCTUnwrap(FaceStickerRenderer(emoji: "😀"))
        // 縦向き動画：バッファは横長、表示は縦長
        let output = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let face = CGRect(x: 0.4, y: 0.6, width: 0.2, height: 0.1)
        let result = renderer.composite(faces: [face], over: output, orientation: .right)
        XCTAssertEqual(result.extent, output.extent)

        let layer = renderer.layer(for: [face], canvasSize: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(layer.extent, CGRect(x: 0, y: 0, width: 1080, height: 1920))
    }
}
