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

/// 選択した動画の情報と最初のフレーム
struct VideoSource {
    let url: URL
    let duration: Double
    /// 回転前のピクセルバッファのサイズ
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let nominalFrameRate: Float
    /// 表示の向き（preferredTransform 適用済み）の最初のフレーム
    let firstFrame: CGImage

    var orientation: CGImagePropertyOrientation {
        CoordinateConverter.orientation(for: preferredTransform)
    }

    static func load(url: URL) async throws -> VideoSource {
        let asset = AVURLAsset(url: url)
        let duration: Double
        let track: AVAssetTrack
        do {
            duration = try await asset.load(.duration).seconds
            guard let first = try await asset.loadTracks(withMediaType: .video).first else {
                throw AppError.loadFailed
            }
            track = first
        } catch {
            throw AppError.loadFailed
        }
        guard duration <= Constants.maxVideoDuration + Constants.durationTolerance else {
            throw AppError.tooLong
        }

        do {
            let (naturalSize, transform, frameRate) = try await track.load(
                .naturalSize, .preferredTransform, .nominalFrameRate)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let firstFrame = try await generator.image(at: .zero).image

            return VideoSource(url: url, duration: duration, naturalSize: naturalSize,
                               preferredTransform: transform, nominalFrameRate: frameRate,
                               firstFrame: firstFrame)
        } catch {
            throw AppError.loadFailed
        }
    }
}
