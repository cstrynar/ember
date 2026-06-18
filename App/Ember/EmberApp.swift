import SwiftUI

/// App entry point. Owns the shared `AppModel` and drives day-rollover / reminder
/// rescheduling on launch and every return to the foreground.
@main
struct EmberApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear { model.onForeground() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { model.onForeground() }
                }
        }
    }
}
