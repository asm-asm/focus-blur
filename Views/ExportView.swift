import AVFoundation
import AVKit
import SwiftUI

struct ExportView: View {
    private enum Phase {
        case exporting
        case saving
        case done
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phase: Phase = .exporting
    @State private var processed = 0
    @State private var total = 0
    @State private var exporter: VideoExporter?
    @State private var hasStarted = false
    @State private var errorMessage: String?
    @State private var showSaveDenied = false
    /// 書き出した動画（確認用。画面を離れるときに消す）
    @State private var exportedURL: URL?
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            if phase == .done, let player, let exportedURL {
                resultView(player: player, url: exportedURL)
            } else {
                progressView
            }
        }
        .padding(24)
        .navigationTitle(phase == .done ? "できあがり" : "書き出し")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await run()
        }
        .onDisappear { discardResult() }
        .errorAlert($errorMessage) { dismiss() }
        .alert(AppError.saveDenied.localizedDescription, isPresented: $showSaveDenied) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
                dismiss()
            }
            Button("閉じる", role: .cancel) { dismiss() }
        } message: {
            Text("設定アプリで「写真」への追加を許可してから、もう一度書き出してください。")
        }
    }

    /// 書き出した動画をくり返し再生して確認する
    private func resultView(player: AVQueuePlayer, url: URL) -> some View {
        VStack(spacing: 16) {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Label("写真ライブラリに保存しました", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            HStack(spacing: 12) {
                ShareLink(item: url) {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    dismiss()
                } label: {
                    Label("調整し直す", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                model.startOver()
            } label: {
                Text("ホームに戻る").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var progressView: some View {
        VStack(spacing: 24) {
            Spacer()
            switch phase {
            case .exporting:
                Text("書き出し中…")
                    .font(.headline)
                ProgressView(value: Double(processed), total: Double(max(total, 1)))
                Text("\(processed) / \(total) フレーム")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            case .saving:
                ProgressView("写真ライブラリに保存しています…")
            case .done:
                EmptyView()
            }
            Spacer()
            switch phase {
            case .exporting:
                Button("キャンセル", role: .cancel) {
                    exporter?.cancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            case .saving, .done:
                EmptyView()
            }
        }
    }

    private func run() async {
        guard let source = model.source, !model.subjects.isEmpty else {
            dismiss()
            return
        }
        let exporter = VideoExporter(source: source, subjects: model.subjects, strength: model.strength,
                                     style: model.style, sticker: model.sticker)
        self.exporter = exporter
        total = exporter.estimatedFrameCount

        // 書き出し中に自動ロックで中断されないようにする
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        do {
            let url = try await withTaskCancellationHandler {
                try await exporter.export { done in processed = done }
            } onCancel: {
                exporter.cancel()
            }
            exportedURL = url
            phase = .saving
            try await PhotoLibrarySaver.save(videoAt: url)
            showResult(url)
        } catch is CancellationError {
            dismiss()
        } catch AppError.saveDenied {
            showSaveDenied = true
        } catch {
            errorMessage = AppError.message(for: error, fallback: .exportFailed)
        }
    }

    private func showResult(_ url: URL) {
        // マナーモードでも音声を確認できるようにする
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let player = AVQueuePlayer()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        self.player = player
        phase = .done
        player.play()
    }

    /// 確認用の再生を止め、一時ファイルを消す
    private func discardResult() {
        player?.pause()
        looper = nil
        player = nil
        if let exportedURL {
            try? FileManager.default.removeItem(at: exportedURL)
        }
        exportedURL = nil
    }
}
