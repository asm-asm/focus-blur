import PhotosUI
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("人物フォーカスぼかし")
                    .font(.title2.bold())
                Text("選んだ人だけくっきり、\nそれ以外を玉ボケでぼかした動画を作ります。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView("動画を読み込んでいます…")
            }
            PhotosPicker(selection: $pickerItem, matching: .videos, preferredItemEncoding: .current) {
                Label("動画を選ぶ", systemImage: "video.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLoading)
            Text("60秒以内の動画を選べます")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .errorAlert($errorMessage)
    }

    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            pickerItem = nil
        }
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                throw AppError.loadFailed
            }
            do {
                let source = try await VideoSource.load(url: movie.url)
                model.start(with: source)
            } catch {
                try? FileManager.default.removeItem(at: movie.url)
                throw error
            }
        } catch {
            errorMessage = AppError.message(for: error, fallback: .loadFailed)
        }
    }
}
