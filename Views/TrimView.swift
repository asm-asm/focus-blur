import AVFoundation
import AVKit
import SwiftUI

/// 使う区間（最大60秒）を選ぶ画面
struct TrimView: View {
    @Environment(AppModel.self) private var model
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var thumbnails: [CGImage] = []
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var isScrubbing = false
    @State private var isConfirming = false
    @State private var errorMessage: String?

    private var duration: Double { model.source?.duration ?? 0 }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Color.black
                if let player {
                    VideoPlayer(player: player)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 6) {
                Text("\(Self.format(start)) 〜 \(Self.format(end))")
                    .font(.headline)
                    .monospacedDigit()
                Text("長さ \(Self.format(end - start))（最大\(Int(Constants.maxVideoDuration))秒）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            TrimSlider(thumbnails: thumbnails, duration: duration, start: $start, end: $end) { time in
                isScrubbing = true
                player?.pause()
                player?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                             toleranceBefore: .zero, toleranceAfter: .zero)
            } onEditingEnded: {
                isScrubbing = false
                playFromStart()
            }
            .frame(height: 56)

            Button {
                Task { await confirm() }
            } label: {
                Group {
                    if isConfirming {
                        ProgressView()
                    } else {
                        Text("次へ")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isConfirming || end - start < Constants.minClipDuration)
        }
        .padding()
        .navigationTitle("区間を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .onDisappear { tearDownPlayer() }
        .errorAlert($errorMessage)
    }

    private func prepare() async {
        guard player == nil, let source = model.source else { return }
        start = source.timeRange.start.seconds
        end = source.timeRange.end.seconds

        let player = AVPlayer(url: source.url)
        // 選んだ区間の終わりまで来たら始めに戻ってくり返す
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { time in
            if !isScrubbing, time.seconds >= end {
                playFromStart()
            }
        }
        self.player = player
        playFromStart()

        thumbnails = await Self.makeThumbnails(url: source.url, duration: source.duration)
    }

    private func playFromStart() {
        guard let player else { return }
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private func tearDownPlayer() {
        player?.pause()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func confirm() async {
        guard let source = model.source else { return }
        isConfirming = true
        defer { isConfirming = false }
        do {
            model.source = try await source.trimmed(start: start, end: end)
            model.faceRect = nil
            player?.pause()
            model.path.append(.subjectSelect)
        } catch {
            errorMessage = AppError.message(for: error, fallback: .loadFailed)
        }
    }

    private static func makeThumbnails(url: URL, duration: Double) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        let count = Constants.trimThumbnailCount
        let times = (0..<count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [CGImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image {
                images.append(image)
            }
        }
        return images
    }

    static func format(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let minutes = Int(total) / 60
        let rest = total - Double(minutes * 60)
        return String(format: "%d:%04.1f", minutes, rest)
    }
}

/// サムネイルの帯の上で、始点と終点のつまみを動かして区間を選ぶ
private struct TrimSlider: View {
    let thumbnails: [CGImage]
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    /// つまみを動かしている間、その位置の時刻で呼ばれる
    let onScrub: (Double) -> Void
    let onEditingEnded: () -> Void

    private let handleWidth: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - handleWidth * 2
            let startX = handleWidth + x(for: start, width: width)
            let endX = handleWidth + x(for: end, width: width)
            ZStack(alignment: .leading) {
                // サムネイルの帯
                HStack(spacing: 0) {
                    ForEach(thumbnails.indices, id: \.self) { index in
                        Image(decorative: thumbnails[index], scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width / CGFloat(max(thumbnails.count, 1)), height: geometry.size.height)
                            .clipped()
                    }
                }
                .frame(width: width, height: geometry.size.height)
                .background(Color.secondary.opacity(0.2))
                .offset(x: handleWidth)

                // 区間外を暗くする
                Color.black.opacity(0.55)
                    .frame(width: max(0, startX - handleWidth))
                    .offset(x: handleWidth)
                Color.black.opacity(0.55)
                    .frame(width: max(0, handleWidth + width - endX))
                    .offset(x: endX)

                // 選んだ区間の枠
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 3)
                    .frame(width: max(0, endX - startX))
                    .offset(x: startX)

                handle(systemImage: "chevron.compact.left")
                    .offset(x: startX - handleWidth)
                    .gesture(drag(width: width) { time in
                        start = min(max(0, time), end - Constants.minClipDuration)
                        // 最大60秒を超えたら終点もいっしょに動かす
                        if end - start > Constants.maxVideoDuration { end = start + Constants.maxVideoDuration }
                        onScrub(start)
                    })
                handle(systemImage: "chevron.compact.right")
                    .offset(x: endX)
                    .gesture(drag(width: width) { time in
                        end = max(min(duration, time), start + Constants.minClipDuration)
                        if end - start > Constants.maxVideoDuration { start = end - Constants.maxVideoDuration }
                        onScrub(end)
                    })
            }
            .coordinateSpace(.named(Self.space))
        }
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        duration > 0 ? CGFloat(time / duration) * width : 0
    }

    private func handle(systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.yellow)
            .frame(width: handleWidth)
            .overlay {
                Image(systemName: systemImage)
                    .font(.body.bold())
                    .foregroundStyle(.black)
            }
            .contentShape(Rectangle().inset(by: -12))
    }

    /// つまみの位置（帯の左端からの x）を時刻に変えて渡す
    private func drag(width: CGFloat, onChange: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(TrimSlider.space))
            .onChanged { value in
                guard width > 0 else { return }
                onChange(Double((value.location.x - handleWidth) / width) * duration)
            }
            .onEnded { _ in onEditingEnded() }
    }

    static let space = "TrimSlider"
}
