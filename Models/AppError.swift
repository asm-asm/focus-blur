import SwiftUI

enum AppError: LocalizedError {
    case tooLong
    case loadFailed
    case noFace
    case exportFailed
    case saveDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .tooLong: return "60秒以内の動画を選んでください。"
        case .loadFailed: return "動画を読み込めませんでした。"
        case .noFace: return "顔が見つかりませんでした。"
        case .exportFailed: return "動画の書き出しに失敗しました。"
        case .saveDenied: return "写真ライブラリへの保存が許可されていません。"
        case .saveFailed: return "写真ライブラリに保存できませんでした。"
        }
    }

    /// AppError 以外のエラーは fallback のメッセージにまとめる
    static func message(for error: Error, fallback: AppError) -> String {
        ((error as? AppError) ?? fallback).localizedDescription
    }
}

extension View {
    /// message が nil 以外のとき日本語のアラートを出す
    func errorAlert(_ message: Binding<String?>, onDismiss: @escaping () -> Void = {}) -> some View {
        alert("エラー",
              isPresented: Binding(get: { message.wrappedValue != nil },
                                   set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel, action: onDismiss)
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
