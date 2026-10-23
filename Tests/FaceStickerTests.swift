import CoreImage
import XCTest
@testable import FocusBlur

final class FaceStickerTests: XCTestCase {

    func testTrackerFollowsMovementWithLittleLag() {
        let tracker = FaceStickerTracker()
        let first = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        XCTAssertEqual(tracker.update(detections: [first], time: 0).map(\.rect), [first])

        let moved = first.offsetBy(dx: 0.05, dy: 0)
        let faces = tracker.update(detections: [moved], time: 1.0 / 30)
        XCTAssertEqual(faces.count, 1)
        // 新しい位置へ stickerSmoothing の割合だけ近づく
        XCTAssertEqual(faces[0].rect.minX, 0.4 + 0.05 * Constants.stickerSmoothing, accuracy: 1e-9)
    }

    func testTrackerPredictsMotionWhileFaceIsMissing() {
        let tracker = FaceStickerTracker()
        let first = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        _ = tracker.update(detections: [first], time: 0)
        let seen = tracker.update(detections: [first.offsetBy(dx: 0.02, dy: 0)], time: 0.1)[0].rect
        let velocity = 0.2 * Constants.stickerVelocitySmoothing  // 測定 0.02 / 0.1秒 を平滑化

        let missing = tracker.update(detections: [], time: 0.2)
        XCTAssertEqual(missing.count, 1)
        // 動いていた向きに進み、少し大きくなる
        XCTAssertEqual(missing[0].rect.midX, seen.midX + velocity * 0.1, accuracy: 1e-9)
        XCTAssertEqual(missing[0].rect.width, seen.width * Constants.stickerMissingGrowth, accuracy: 1e-9)
    }

    func testTrackerDropsFaceAfterHoldDuration() {
        let tracker = FaceStickerTracker()
        _ = tracker.update(detections: [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)], time: 0)
        XCTAssertEqual(tracker.update(detections: [], time: Constants.stickerHoldDuration - 0.01).count, 1)
        XCTAssertEqual(tracker.update(detections: [], time: Constants.stickerHoldDuration + 0.01).count, 0)
    }

    func testTrackerKeepsIDsAndAddsNewFaces() {
        let tracker = FaceStickerTracker()
        let a = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2)
        let firstID = tracker.update(detections: [a], time: 0)[0].id
        let faces = tracker.update(detections: [b, a], time: 0.03)
        XCTAssertEqual(faces.count, 2)
        XCTAssertEqual(faces.first { $0.rect.minX < 0.5 }?.id, firstID)
        XCTAssertNotEqual(faces.first { $0.rect.minX > 0.5 }?.id, firstID)
    }

    func testMergePrefersFaceOverHeadOfSamePerson() {
        let face = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        let sameHead = CGRect(x: 0.41, y: 0.42, width: 0.12, height: 0.12)
        let otherHead = CGRect(x: 0.8, y: 0.4, width: 0.1, height: 0.1)
        XCTAssertEqual(FaceStickerTracker.merge(faces: [face], heads: [sameHead, otherHead]), [face, otherHead])
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
