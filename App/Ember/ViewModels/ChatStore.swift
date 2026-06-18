import Foundation

/// One message shown in the Coach chat (text only; tool turns are hidden).
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

/// Owns the Coach conversation: the visible messages and the underlying API history.
@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var draft = ""
    @Published var errorText: String?

    /// Full Messages-API history including tool_use / tool_result turns.
    private var apiMessages: [[String: Any]] = []

    func send(app: AppModel) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        guard let key = app.currentAPIKey(), !key.isEmpty else {
            errorText = "Add your API key in Settings → Coach."
            return
        }

        draft = ""
        errorText = nil
        messages.append(ChatMessage(role: .user, text: text))
        apiMessages.append(["role": "user", "content": text])
        isThinking = true

        let agent = CoachAgent(backend: AnthropicClient(apiKey: key),
                               tools: CoachTools(app: app),
                               model: app.coachModel)
        let system = CoachAgent.systemPrompt(app: app)

        do {
            let result = try await agent.run(systemPrompt: system, messages: apiMessages)
            apiMessages = result.messages
            let reply = result.reply.isEmpty ? "(no response)" : result.reply
            messages.append(ChatMessage(role: .assistant, text: reply))
        } catch {
            errorText = (error as? CoachError)?.userMessage ?? "Something went wrong. Please try again."
        }
        isThinking = false
    }

    /// Flush the current conversation: visible messages, API history, and transient state.
    func reset() {
        messages = []
        apiMessages = []
        isThinking = false
        errorText = nil
        draft = ""
    }
}
