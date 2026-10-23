import AVFoundation
import PhotosUI
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCameraDenied = false

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
            VStack(spacing: 12) {
                if CameraRecorder.isAvailable {
                    Button {
                        Task { await openCamera() }
                    } label: {
                        Label("カメラで撮る", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                PhotosPicker(selection: $pickerItem, matching: .videos, preferredItemEncoding: .current) {
                    Label("動画を選ぶ", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .disabled(isLoading)
            Text("60秒を超える動画は、次の画面で使う区間を選べます")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraRecorder { url in
                isShowingCamera = false
                guard let url else { return }
                Task { await loadRecording(url) }
            }
            .ignoresSafeArea()
        }
        .errorAlert($errorMessage)
        .alert("カメラへのアクセスが許可されていません", isPresented: $showCameraDenied) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("設定アプリで「カメラ」を許可すると、このアプリから撮影できます。")
        }
    }

    private func openCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                isShowingCamera = true
            } else {
                showCameraDenied = true
            }
        default:
            showCameraDenied = true
        }
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
            await loadMovie(at: movie.url)
        } catch {
            errorMessage = AppError.message(for: error, fallback: .loadFailed)
        }
    }

    private func loadRecording(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        // 撮ったままの動画もカメラロールに残しておく（加工後だけだと元の映像が失われるため）。
        // 保存できなくても編集は続けられるようにする
        try? await PhotoLibrarySaver.save(videoAt: url)
        await loadMovie(at: url)
    }

    private func loadMovie(at url: URL) async {
        do {
            let source = try await VideoSource.load(url: url)
            model.start(with: source)
        } catch {
            try? FileManager.default.removeItem(at: url)
            errorMessage = AppError.message(for: error, fallback: .loadFailed)
        }
    }
}
