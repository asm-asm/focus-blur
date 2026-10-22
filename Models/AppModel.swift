import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Route: Hashable {
        case subjectSelect
        case adjust
        case export
    }

    var path: [Route] = []
    var source: VideoSource?
    /// 対象人物の顔。最初のフレーム（表示の向き）での Vision 正規化座標
    var faceRect: CGRect?
    /// 最初のフレームで検出したすべての顔（Vision 正規化座標）
    var faces: [CGRect] = []
    var strength: Double = Constants.defaultStrength
    var sticker = StickerSettings()

    func start(with source: VideoSource) {
        discardSource()
        self.source = source
        path = [.subjectSelect]
    }

    /// ホームに戻り、コピーした一時ファイルを消す
    func startOver() {
        path = []
        discardSource()
    }

    private func discardSource() {
        if let url = source?.url {
            try? FileManager.default.removeItem(at: url)
        }
        source = nil
        faceRect = nil
        faces = []
        strength = Constants.defaultStrength
        sticker = StickerSettings()
    }
}
