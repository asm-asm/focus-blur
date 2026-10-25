import CoreGraphics
import Foundation

/// ぼかしの見た目
struct BlurStyle: Equatable {
    var preset: BlurPreset = .natural
    /// 人から離れるほどぼかしを強くする
    var isGradient = false
}

enum BlurPreset: String, CaseIterable, Identifiable {
    case natural
    case film
    case dreamy
    case monoBackground

    var id: Self { self }

    var label: String {
        switch self {
        case .natural: return "ナチュラル"
        case .film: return "フィルム"
        case .dreamy: return "ドリーミー"
        case .monoBackground: return "モノクロ背景"
        }
    }

    var systemImage: String {
        switch self {
        case .natural: return "camera.aperture"
        case .film: return "film"
        case .dreamy: return "sparkles"
        case .monoBackground: return "circle.lefthalf.filled"
        }
    }
}

/// ピントを合わせる人の切り替え点。time 以降はこの顔の人を追う
struct SubjectKey: Identifiable {
    let id = UUID()
    /// 元動画の時刻（秒）
    var time: Double
    /// その時刻のフレーム（表示の向き）での Vision 正規化座標
    var faceRect: CGRect
    /// 一覧に出す顔の切り抜き
    var thumbnail: CGImage?
}
