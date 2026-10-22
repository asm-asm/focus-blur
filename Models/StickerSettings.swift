import Foundation

/// 顔に貼る絵文字の設定
struct StickerSettings: Equatable {
    enum Target: String, CaseIterable, Identifiable {
        case subject
        case others
        case everyone

        var id: Self { self }

        var label: String {
            switch self {
            case .subject: return "ピントの人"
            case .others: return "ほかの人"
            case .everyone: return "全員"
            }
        }
    }

    static let presets = ["😀", "😎", "🥰", "🤪", "😺", "🐶", "🐰", "🐻", "⭐️", "❤️", "🌸", "🙈"]

    /// nil なら絵文字なし
    var emoji: String?
    var target: Target = .subject
}
