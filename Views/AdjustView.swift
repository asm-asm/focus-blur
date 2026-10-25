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
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 設定が増えてもプレビューが小さくなりすぎないよう、設定はスクロールできる枠に入れる
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !hasMask {
                        Text("このフレームでは人物の輪郭を取得できませんでした。書き出し時は追跡しながら取得し直します。")
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

                    StylePicker(style: $model.style)

                    StickerPicker(sticker: $model.sticker)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 320)

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
        .onChange(of: model.sticker) {
            scheduleRender(debounce: false)
        }
        .onChange(of: model.style) {
            scheduleRender(debounce: false)
        }
    }

    /// 最初の切り替え点のフレームでプレビューする
    private func prepare() async {
        guard renderer == nil, let source = model.source, let first = model.subjects.first else { return }
        let frame: CGImage
        if abs(first.time - source.timeRange.start.seconds) < Constants.subjectSwitchTolerance {
            frame = source.firstFrame
        } else if let loaded = try? await source.frame(at: first.time) {
            frame = loaded
        } else {
            return
        }
        let faceRect = first.faceRect
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
        let sticker = model.sticker
        let style = model.style
        renderTask = Task {
            if debounce {
                try? await Task.sleep(for: Constants.previewDebounce)
            }
            guard !Task.isCancelled, let renderer else { return }
            let image = await renderer.render(strength: strength, style: style, sticker: sticker)
            guard !Task.isCancelled else { return }
            preview = image
        }
    }
}

/// ぼかしのプリセットと、人から離れるほど強くするかを選ぶ
private struct StylePicker: View {
    @Binding var style: BlurStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BlurPreset.allCases) { preset in
                        let isSelected = style.preset == preset
                        Button {
                            style.preset = preset
                        } label: {
                            Label(preset.label, systemImage: preset.systemImage)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12)))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
            }
            Toggle("人から離れるほど強くぼかす", isOn: $style.isGradient)
        }
    }
}

/// 顔に貼る絵文字と、貼る相手を選ぶ
private struct StickerPicker: View {
    @Binding var sticker: StickerSettings
    @State private var customEmoji = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("顔に絵文字")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    choice(nil) {
                        Image(systemName: "nosign")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(StickerSettings.presets, id: \.self) { emoji in
                        choice(emoji) { Text(emoji).font(.title2) }
                    }
                    // プリセット以外は絵文字キーボードで入力（最後の1文字を使う）
                    TextField("他", text: $customEmoji)
                        .multilineTextAlignment(.center)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.accentColor, lineWidth: isCustomSelected ? 2 : 0)
                        }
                        .onChange(of: customEmoji) { _, text in
                            guard let last = text.last else { return }
                            let emoji = String(last)
                            if customEmoji != emoji { customEmoji = emoji }
                            sticker.emoji = emoji
                        }
                }
                .padding(2)
            }
            if sticker.emoji != nil {
                Picker("貼る相手", selection: $sticker.target) {
                    ForEach(StickerSettings.Target.allCases) { target in
                        Text(target.label).tag(target)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var isCustomSelected: Bool {
        guard let emoji = sticker.emoji else { return false }
        return !StickerSettings.presets.contains(emoji) && emoji == customEmoji
    }

    private func choice<Label: View>(_ emoji: String?, @ViewBuilder label: () -> Label) -> some View {
        Button {
            sticker.emoji = emoji
        } label: {
            label()
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor, lineWidth: sticker.emoji == emoji ? 2 : 0)
                }
        }
        .buttonStyle(.plain)
    }
}
