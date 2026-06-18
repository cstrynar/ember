import SwiftUI

/// API key entry + model selection for the coach.
struct CoachSettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var keyDraft = ""

    var body: some View {
        Form {
            Section {
                SecureField("sk-ant-…", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("Save key") {
                        app.saveAPIKey(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        keyDraft = ""
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if app.hasAPIKey {
                        Spacer()
                        Button("Remove", role: .destructive) { app.clearAPIKey() }
                    }
                }
                if app.hasAPIKey {
                    Label("Key saved", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Anthropic API key")
            } footer: {
                Text("Stored only in your device Keychain. Used to talk directly to Anthropic — never sent anywhere else. Get a key at console.anthropic.com.")
            }

            Section {
                Picker("Model", selection: Binding(
                    get: { app.coachModel },
                    set: { app.setCoachModel($0) })
                ) {
                    Text("Sonnet 4.6 (recommended)").tag("claude-sonnet-4-6")
                    Text("Opus 4.8").tag("claude-opus-4-8")
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Sonnet is fast and inexpensive; Opus is the most capable. You pay Anthropic per message.")
            }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
    }
}
