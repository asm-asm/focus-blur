import SwiftUI

@main
struct FocusBlurApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: AppModel.Route.self) { route in
                    switch route {
                    case .trim: TrimView()
                    case .subjectSelect: SubjectSelectView()
                    case .adjust: AdjustView()
                    case .export: ExportView()
                    }
                }
        }
    }
}
