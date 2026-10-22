import Photos

enum PhotoLibrarySaver {
    /// 追加のみの権限で動画をカメラロールに保存する
    static func save(videoAt url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AppError.saveDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            throw AppError.saveFailed
        }
    }
}
