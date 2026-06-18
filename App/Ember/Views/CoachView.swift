import SwiftUI

/// The Coach tab: a chat with the AI coach (non-streaming, with a thinking indicator).
struct CoachView: View {
    @EnvironmentObject var app: AppModel
    @StateObject private var chat = ChatStore()
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if app.hasAPIKey {
                    chatBody
                } else {
                    noKey
                }
            }
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if app.hasAPIKey {
                        Button(role: .destructive) { showingClearConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Clear conversation")
                        .disabled(chat.isThinking
                                  || (chat.messages.isEmpty && chat.errorText == nil))
                    }
                }
            }
            .confirmationDialog("Clear this conversation?",
                                isPresented: $showingClearConfirm,
                                titleVisibility: .visible) {
                Button("Clear conversation", role: .destructive) { chat.reset() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the current chat. Saved coach memory is kept.")
            }
        }
    }

    private var noKey: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.orange)
            Text("Add your Anthropic API key").font(.headline)
            Text("In Settings → Coach, paste your key to start chatting with your coach.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if chat.messages.isEmpty {
                            Text("Ask me to plan meals, log food, suggest a workout, or check your macros.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                        ForEach(chat.messages) { ChatBubble(message: $0) }
                        if chat.isThinking { ThinkingRow() }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: chat.messages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: chat.isThinking) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            if let error = chat.errorText {
                Text(error).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            inputBar
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask your coach…", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(chat.isThinking)
            Button {
                Task { await chat.send(app: app) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(chat.isThinking || chat.draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(message.role == .user ? Color.orange.opacity(0.2) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

private struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Thinking…").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
