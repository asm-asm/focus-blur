import SwiftUI

/// ピントを合わせる人を選ぶ。スライダーで時点を動かして別の人をタップすると、その時点から切り替わる
struct SubjectSelectView: View {
    @Environment(AppModel.self) private var model
    @State private var time: Double = 0
    @State private var frame: CGImage?
    /// 表示中のフレームで検出した顔（Vision 正規化座標）
    @State private var faces: [CGRect] = []
    @State private var isLoadingFrame = true
    @State private var loadTask: Task<Void, Never>?

    private var clipStart: Double { model.source?.timeRange.start.seconds ?? 0 }
    private var clipEnd: Double { model.source?.timeRange.end.seconds ?? 0 }

    /// 表示中の時点にある切り替え点
    private var keyAtCurrentTime: SubjectKey? {
        model.subjects.first { abs($0.time - time) < Constants.subjectSwitchTolerance }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(model.subjects.isEmpty
                 ? "ぼかさない人の顔をタップしてください"
                 : "途中で切り替えるときは、その時点に動かして顔をタップ")
                .font(.headline)
                .multilineTextAlignment(.center)

            frameView

            if !isLoadingFrame && faces.isEmpty {
                Text("この時点では顔が見つかりません。スライダーで別の時点を選んでください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Slider(value: $time, in: clipStart...max(clipEnd, clipStart + 0.1))
                Text(TrimView.format(time - clipStart))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if !model.subjects.isEmpty {
                keyList
            }

            Button {
                model.path.append(.adjust)
            } label: {
                Text("次へ").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.subjects.isEmpty)
        }
        .padding()
        .navigationTitle("対象を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            time = model.subjects.first?.time ?? clipStart
            await loadFrame(at: time, autoSelect: model.subjects.isEmpty)
        }
        .onChange(of: time) { _, newValue in
            scheduleLoad(at: newValue)
        }
    }

    private var frameView: some View {
        GeometryReader { geometry in
            if let frame {
                let imageRect = CoordinateConverter.aspectFitRect(
                    content: CGSize(width: frame.width, height: frame.height), in: geometry.size)
                let selectedRect = keyAtCurrentTime?.faceRect
                ZStack(alignment: .topLeading) {
                    Image(decorative: frame, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    ForEach(faces.indices, id: \.self) { index in
                        let rect = CoordinateConverter.normalizedRectToView(faces[index], imageRect: imageRect)
                        let isSelected = faces[index] == selectedRect
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.yellow : Color.white.opacity(0.6),
                                    lineWidth: isSelected ? 3 : 1.5)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                    if isLoadingFrame {
                        ProgressView()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    select(at: location, imageRect: imageRect, frame: frame)
                }
            } else {
                ProgressView()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    /// 切り替え点の一覧。タップでその時点へ、× で削除
    private var keyList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.subjects) { key in
                    Button {
                        time = key.time
                    } label: {
                        VStack(spacing: 4) {
                            Group {
                                if let thumbnail = key.thumbnail {
                                    Image(decorative: thumbnail, scale: 1)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 48, height: 48)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(Color.yellow, lineWidth: key.id == keyAtCurrentTime?.id ? 3 : 0)
                            }
                            Text("\(TrimView.format(key.time - clipStart))〜")
                                .font(.caption2)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            model.subjects.removeAll { $0.id == key.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .gray)
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: フレームの読み込み

    /// スライダーを動かしている間は読み込みを待ち、止まったら読み込む
    private func scheduleLoad(at seconds: Double) {
        loadTask?.cancel()
        // 表示中のフレームと時点がずれている間はタップを受け付けない
        isLoadingFrame = true
        loadTask = Task {
            try? await Task.sleep(for: Constants.previewDebounce)
            guard !Task.isCancelled else { return }
            await loadFrame(at: seconds, autoSelect: false)
        }
    }

    private func loadFrame(at seconds: Double, autoSelect: Bool) async {
        guard let source = model.source else { return }
        isLoadingFrame = true
        let image: CGImage?
        if abs(seconds - clipStart) < Constants.subjectSwitchTolerance {
            image = source.firstFrame
        } else {
            image = try? await source.frame(at: seconds)
        }
        guard !Task.isCancelled, let image else {
            isLoadingFrame = false
            return
        }
        let found = await Task.detached(priority: .userInitiated) {
            SubjectTracker.detectFaces(in: image)
        }.value
        guard !Task.isCancelled else { return }
        frame = image
        faces = found
        isLoadingFrame = false
        // 最初の時点で顔が1つだけなら、その人を選んでおく
        if autoSelect, found.count == 1 {
            setSubject(found[0], in: image)
        }
    }

    // MARK: 選択

    /// タップ位置を含む顔（複数あれば小さい方）、なければ一番近い顔を選ぶ
    private func select(at location: CGPoint, imageRect: CGRect, frame: CGImage) {
        let rects = faces.map { CoordinateConverter.normalizedRectToView($0, imageRect: imageRect) }
        guard !rects.isEmpty, !isLoadingFrame else { return }
        func distance(_ rect: CGRect) -> CGFloat {
            hypot(rect.midX - location.x, rect.midY - location.y)
        }
        let index = rects.indices.filter { rects[$0].contains(location) }
            .min { rects[$0].width * rects[$0].height < rects[$1].width * rects[$1].height }
            ?? rects.indices.min { distance(rects[$0]) < distance(rects[$1]) }
        if let index {
            setSubject(faces[index], in: frame)
        }
    }

    /// 表示中の時点から、この顔の人にピントを合わせる
    private func setSubject(_ faceRect: CGRect, in frame: CGImage) {
        let key = SubjectKey(time: time, faceRect: faceRect, thumbnail: Self.crop(faceRect, from: frame))
        model.subjects.removeAll { abs($0.time - time) < Constants.subjectSwitchTolerance }
        model.subjects.append(key)
        model.subjects.sort { $0.time < $1.time }
    }

    private static func crop(_ faceRect: CGRect, from image: CGImage) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let padded = faceRect.insetBy(dx: -faceRect.width * 0.2, dy: -faceRect.height * 0.2)
        // Vision は左下原点、CGImage の切り抜きは左上原点
        let rect = CGRect(x: padded.minX * width, y: (1 - padded.maxY) * height,
                          width: padded.width * width, height: padded.height * height)
        return image.cropping(to: rect.integral)
    }
}
