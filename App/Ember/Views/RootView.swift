import SwiftUI

/// Top-level tab shell. Food & Settings are live (P2); Coach (P4) and Train (P3) are
/// placeholders until their phases land.
struct RootView: View {
    var body: some View {
        TabView {
            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }
            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
            TrainView()
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
