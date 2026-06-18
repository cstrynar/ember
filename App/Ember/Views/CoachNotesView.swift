import SwiftUI

/// Weekly maintenance reviews: generate one (when a key is set) and read past reports.
struct CoachNotesView: View {
    @EnvironmentObject var app: AppModel
    @State private var isRunning = false
    @State private var errorText: String?

    var body: some View {
        List {
            if app.hasAPIKey {
                Section {
                    Button { Task { await run() } } label: {
                        HStack {
                            Label(isRunning ? "Generating…" : "Generate this week's review",
                                  systemImage: "sparkles.rectangle.stack")
                            if isRunning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isRunning)
                } footer: {
                    Text(app.isWeeklyReviewDue
                         ? "It's been about a week — a good time to review."
                         : "Runs your coach over the past week and the friction log to suggest improvements.")
                }
            } else {
                Section {
                    Text("Add your API key in Settings → Coach to enable weekly reviews.")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }

            if app.reports.isEmpty {
                Section { Text("No reviews yet.").foregroundStyle(.secondary) }
            } else {
                ForEach(app.reports) { report in
                    Section(report.id) {
                        Text(.init(report.markdown)).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Coach Notes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run() async {
        isRunning = true
        errorText = nil
        do {
            _ = try await app.generateWeeklyReview()
        } catch {
            errorText = (error as? CoachError)?.userMessage ?? "Couldn't generate the review."
        }
        isRunning = false
    }
}
