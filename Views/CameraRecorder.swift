import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 標準カメラで動画を撮る。撮った動画は一時ディレクトリに移して URL を返す（キャンセルなら nil）
struct CameraRecorder: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void

        init(onFinish: @escaping (URL?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let recorded = info[.mediaURL] as? URL else {
                onFinish(nil)
                return
            }
            let ext = recorded.pathExtension.isEmpty ? "mov" : recorded.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("recorded-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            do {
                try FileManager.default.moveItem(at: recorded, to: destination)
                onFinish(destination)
            } catch {
                onFinish(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
