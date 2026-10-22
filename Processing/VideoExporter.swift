import AVFoundation
import CoreImage

/// 全フレームを処理して書き出す。映像は再エンコード、音声はパススルーでコピーする。
///
/// HDR（10bit）動画について：MVP では 8bit BGRA で読み出し、BT.709（SDR）として書き出す。
/// HDR のトーンマッピングは行わないため、HDR 動画は元より色や明るさが変わることがある。
final class VideoExporter: @unchecked Sendable {
    private let source: VideoSource
    private let faceRect: CGRect
    private let strength: Double
    private let lock = NSLock()
    private var cancelled = false
    private let videoQueue = DispatchQueue(label: "VideoExporter.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "VideoExporter.audio", qos: .userInitiated)

    /// 総フレーム数の目安（進捗表示用）
    let estimatedFrameCount: Int

    init(source: VideoSource, faceRect: CGRect, strength: Double) {
        self.source = source
        self.faceRect = faceRect
        self.strength = strength
        estimatedFrameCount = max(1, Int((source.duration * Double(source.nominalFrameRate)).rounded()))
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    /// - Parameter progress: 処理済みフレーム数。メインスレッドで呼ばれる
    /// - Returns: 一時ディレクトリに書き出した .mov（保存後に呼び出し側で削除する）
    func export(progress: @escaping (Int) -> Void) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("focusblur-\(UUID().uuidString)")
            .appendingPathExtension("mov")
        do {
            try await run(outputURL: outputURL, progress: progress)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            if error is CancellationError { throw error }
            throw (error as? AppError) ?? AppError.exportFailed
        }
    }

    private func run(outputURL: URL, progress: @escaping (Int) -> Void) async throws {
        let asset = AVURLAsset(url: source.url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.loadFailed
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let (formats, dataRate) = try await videoTrack.load(.formatDescriptions, .estimatedDataRate)
        let audioFormat = try await audioTrack?.load(.formatDescriptions).first

        let width = Int(source.naturalSize.width.rounded())
        let height = Int(source.naturalSize.height.rounded())
        let frameRate = Double(source.nominalFrameRate > 0 ? source.nominalFrameRate : 30)

        // MARK: 読み出し

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw AppError.exportFailed }
        reader.add(videoOutput)

        // MARK: 書き出し

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let isHEVC = formats.first.map { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC } ?? false
        let bitRate = dataRate > 0
            ? Double(dataRate)
            : Double(width * height) * frameRate * Constants.fallbackBitsPerPixel
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: isHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        // ピクセルは回転前の向きのまま処理し、向きは transform で元動画と同じにする
        videoInput.transform = source.preferredTransform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        guard writer.canAdd(videoInput) else { throw AppError.exportFailed }
        writer.add(videoInput)

        // 音声は再エンコードせずにそのままコピー
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioOutput = output
                audioInput = input
            }
        }

        guard reader.startReading(), writer.startWriting() else {
            reader.cancelReading()
            writer.cancelWriting()
            throw AppError.exportFailed
        }
        writer.startSession(atSourceTime: .zero)

        let pipeline = FocusPipeline(bufferSize: source.naturalSize, orientation: source.orientation,
                                     faceRect: faceRect, strength: CGFloat(strength))
        let outputBounds = CGRect(x: 0, y: 0, width: width, height: height)
        let total = estimatedFrameCount

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let group = DispatchGroup()

            // MARK: 映像
            group.enter()
            var videoFinished = false
            var processed = 0
            videoInput.requestMediaDataWhenReady(on: videoQueue) { [self] in
                guard !videoFinished else { return }
                func finish() {
                    videoInput.markAsFinished()
                    videoFinished = true
                    group.leave()
                }
                while videoInput.isReadyForMoreMediaData {
                    guard !isCancelled, writer.status == .writing,
                          let sample = videoOutput.copyNextSampleBuffer() else {
                        finish()
                        return
                    }
                    let appended = autoreleasepool {
                        appendProcessedFrame(sample, pipeline: pipeline, adaptor: adaptor, bounds: outputBounds)
                    }
                    guard appended else {
                        finish()
                        return
                    }
                    processed += 1
                    if processed % Constants.progressReportInterval == 0 {
                        let done = min(processed, total)
                        DispatchQueue.main.async { progress(done) }
                    }
                }
            }

            // MARK: 音声
            if let audioInput, let audioOutput {
                group.enter()
                var audioFinished = false
                audioInput.requestMediaDataWhenReady(on: audioQueue) { [self] in
                    guard !audioFinished else { return }
                    while audioInput.isReadyForMoreMediaData {
                        guard !isCancelled, writer.status == .writing,
                              let sample = audioOutput.copyNextSampleBuffer(),
                              audioInput.append(sample) else {
                            audioInput.markAsFinished()
                            audioFinished = true
                            group.leave()
                            return
                        }
                    }
                }
            }

            group.notify(queue: videoQueue) { [self] in
                if isCancelled {
                    reader.cancelReading()
                    writer.cancelWriting()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard reader.status != .failed, writer.status == .writing else {
                    reader.cancelReading()
                    writer.cancelWriting()
                    continuation.resume(throwing: AppError.exportFailed)
                    return
                }
                writer.finishWriting {
                    if writer.status == .completed {
                        DispatchQueue.main.async { progress(total) }
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AppError.exportFailed)
                    }
                }
            }
        }
    }

    /// 1フレームを処理して書き出す。失敗したら false
    private func appendProcessedFrame(_ sample: CMSampleBuffer, pipeline: FocusPipeline,
                                      adaptor: AVAssetWriterInputPixelBufferAdaptor, bounds: CGRect) -> Bool {
        // 映像以外のサンプル（ピクセルバッファを持たないもの）は飛ばす
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return true }
        // タイムスタンプは元のものをそのまま使う
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        let output = pipeline.process(pixelBuffer, time: time.seconds)

        guard let pool = adaptor.pixelBufferPool, let outputBuffer = PixelBufferFactory.make(from: pool) else {
            return false
        }
        RenderContext.shared.render(output, to: outputBuffer, bounds: bounds, colorSpace: RenderContext.videoColorSpace)
        return adaptor.append(outputBuffer, withPresentationTime: time)
    }
}
