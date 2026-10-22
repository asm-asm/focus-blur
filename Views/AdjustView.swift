import SwiftUI

struct AdjustView: View {
    @Environment(AppModel.self) private var model
    @State private var renderer: PreviewRenderer?
    @State private var preview: CGImage?
    @State private var hasMask = true
    @State private var renderTask: Task<Void, Never>?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 20) {
            ZStack {
                Color.black
                if let preview {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !hasMask {
                Text("最初のフレームでは人物の輪郭を取得できませんでした。書き出し時は追跡しながら取得し直します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ぼかしの強さ")
                    Spacer()
                    Text("\(Int((model.strength * 100).rounded()))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.strength, in: 0...1)
            }

            Button {
                model.path.append(.export)
            } label: {
                Label("書き出す", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .navigationTitle("ぼかしの調整")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .onChange(of: model.strength) {
            scheduleRender(debounce: true)
        }
    }

    private func prepare() async {
        guard renderer == nil, let frame = model.source?.firstFrame, let faceRect = model.faceRect else { return }
        let created = await Task.detached(priority: .userInitiated) {
            PreviewRenderer(firstFrame: frame, faceRect: faceRect)
        }.value
        renderer = created
        hasMask = created.hasMask
        scheduleRender(debounce: false)
    }

    /// スライダーを動かすたびに描き直すと重いので、止まってから描く
    private func scheduleRender(debounce: Bool) {
        renderTask?.cancel()
        let strength = model.strength
        renderTask = Task {
            if debounce {
                try? await Task.sleep(for: Constants.previewDebounce)
            }
            guard !Task.isCancelled, let renderer else { return }
            let image = await renderer.render(strength: strength)
            guard !Task.isCancelled else { return }
            preview = image
        }
    }
}
