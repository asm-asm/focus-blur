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

    var body: some View {
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("保存しました")
                    .font(.title2.bold())
            }
            Spacer()
            switch phase {
            case .exporting:
                Button("キャンセル", role: .cancel) {
                    exporter?.cancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            case .saving:
                EmptyView()
            case .done:
                Button {
                    model.startOver()
                } label: {
                    Text("ホームに戻る").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .navigationTitle("書き出し")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await run()
        }
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

    private func run() async {
        guard let source = model.source, let faceRect = model.faceRect else {
            dismiss()
            return
        }
        let exporter = VideoExporter(source: source, faceRect: faceRect, strength: model.strength,
                                     sticker: model.sticker)
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
            defer { try? FileManager.default.removeItem(at: url) }
            phase = .saving
            try await PhotoLibrarySaver.save(videoAt: url)
            phase = .done
        } catch is CancellationError {
            dismiss()
        } catch AppError.saveDenied {
            showSaveDenied = true
        } catch {
            errorMessage = AppError.message(for: error, fallback: .exportFailed)
        }
    }
}
