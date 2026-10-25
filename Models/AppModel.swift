import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum Route: Hashable {
        case trim
        case subjectSelect
        case adjust
        case export
    }

    var path: [Route] = []
    var source: VideoSource?
    /// ピントを合わせる人の切り替え点（時刻順）
    var subjects: [SubjectKey] = []
    var strength: Double = Constants.defaultStrength
    var style = BlurStyle()
    var sticker = StickerSettings()

    func start(with source: VideoSource) {
        discardSource()
        self.source = source
        path = [.trim]
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
        subjects = []
        strength = Constants.defaultStrength
        style = BlurStyle()
        sticker = StickerSettings()
    }
}
