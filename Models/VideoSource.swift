import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

/// PhotosPicker で選んだ動画を一時ディレクトリにコピーしたもの
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

/// 選択した動画の情報と、使う区間・その最初のフレーム
struct VideoSource {
    let url: URL
    /// 元動画全体の長さ（秒）
    let duration: Double
    /// 回転前のピクセルバッファのサイズ
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let nominalFrameRate: Float
    /// 書き出す区間（最大 Constants.maxVideoDuration 秒）
    private(set) var timeRange: CMTimeRange
    /// 表示の向き（preferredTransform 適用済み）の、区間の最初のフレーム
    private(set) var firstFrame: CGImage

    var orientation: CGImagePropertyOrientation {
        CoordinateConverter.orientation(for: preferredTransform)
    }

    /// 区間の長さ（秒）
    var clipDuration: Double { timeRange.duration.seconds }

    /// 動画を読み込む。区間は先頭から最大60秒
    static func load(url: URL) async throws -> VideoSource {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw AppError.loadFailed
            }
            let (naturalSize, transform, frameRate) = try await track.load(
                .naturalSize, .preferredTransform, .nominalFrameRate)
            let length = CMTimeMinimum(duration, CMTime(seconds: Constants.maxVideoDuration, preferredTimescale: 600))
            let range = CMTimeRange(start: .zero, duration: length)
            return VideoSource(url: url, duration: duration.seconds, naturalSize: naturalSize,
                               preferredTransform: transform, nominalFrameRate: frameRate,
                               timeRange: range, firstFrame: try await frame(of: asset, at: .zero))
        } catch {
            throw AppError.loadFailed
        }
    }

    /// 区間を start〜end 秒に変えたもの
    func trimmed(start: Double, end: Double) async throws -> VideoSource {
        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        let endTime = CMTime(seconds: end, preferredTimescale: 600)
        var trimmed = self
        trimmed.timeRange = CMTimeRange(start: startTime, end: endTime)
        trimmed.firstFrame = try await frame(at: start)
        return trimmed
    }

    /// 指定した時刻（秒）のフレーム（表示の向き）
    func frame(at seconds: Double) async throws -> CGImage {
        do {
            return try await Self.frame(of: AVURLAsset(url: url), at: CMTime(seconds: seconds, preferredTimescale: 600))
        } catch {
            throw AppError.loadFailed
        }
    }

    private static func frame(of asset: AVAsset, at time: CMTime) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: time).image
    }
}
