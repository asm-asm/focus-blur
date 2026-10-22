import SwiftUI

struct SubjectSelectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 検出した顔（Vision 正規化座標）
    @State private var faces: [CGRect] = []
    @State private var selectedIndex: Int?
    @State private var isDetecting = true
    @State private var showNoFaceAlert = false

    var body: some View {
        VStack(spacing: 16) {
            Text("ぼかさない人の顔をタップしてください")
                .font(.headline)
            if let frame = model.source?.firstFrame {
                GeometryReader { geometry in
                    let imageRect = CoordinateConverter.aspectFitRect(
                        content: CGSize(width: frame.width, height: frame.height), in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: frame, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        ForEach(faces.indices, id: \.self) { index in
                            let rect = CoordinateConverter.normalizedRectToView(faces[index], imageRect: imageRect)
                            let isSelected = index == selectedIndex
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.yellow : Color.white.opacity(0.6),
                                        lineWidth: isSelected ? 3 : 1.5)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                        if isDetecting {
                            ProgressView()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        select(at: location, imageRect: imageRect)
                    }
                }
            }
            Button {
                guard let selectedIndex else { return }
                model.faceRect = faces[selectedIndex]
                model.faces = faces
                model.path.append(.adjust)
            } label: {
                Text("次へ").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedIndex == nil)
        }
        .padding()
        .navigationTitle("対象を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .task { await detectFaces() }
        .alert(AppError.noFace.localizedDescription, isPresented: $showNoFaceAlert) {
            Button("戻る") { dismiss() }
        } message: {
            Text("顔がはっきり映っている動画を選んでください。")
        }
    }

    private func detectFaces() async {
        guard faces.isEmpty, let frame = model.source?.firstFrame else { return }
        let found = await Task.detached(priority: .userInitiated) {
            SubjectTracker.detectFaces(in: frame)
        }.value
        isDetecting = false
        faces = found
        if found.isEmpty {
            showNoFaceAlert = true
        } else if found.count == 1 {
            selectedIndex = 0
        }
    }

    /// タップ位置を含む顔（複数あれば小さい方）、なければ一番近い顔を選ぶ
    private func select(at location: CGPoint, imageRect: CGRect) {
        let rects = faces.map { CoordinateConverter.normalizedRectToView($0, imageRect: imageRect) }
        guard !rects.isEmpty else { return }
        if let hit = rects.indices.filter({ rects[$0].contains(location) })
            .min(by: { rects[$0].width * rects[$0].height < rects[$1].width * rects[$1].height }) {
            selectedIndex = hit
            return
        }
        func distance(_ rect: CGRect) -> CGFloat {
            hypot(rect.midX - location.x, rect.midY - location.y)
        }
        selectedIndex = rects.indices.min(by: { distance(rects[$0]) < distance(rects[$1]) })
    }
}
