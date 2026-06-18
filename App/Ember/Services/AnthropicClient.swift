import Foundation

/// A single client tool call requested by the model.
struct ToolUse {
    let id: String
    let name: String
    let input: [String: Any]
}

/// Parsed result of one Messages API turn.
struct AnthropicResponse {
    /// Raw assistant content blocks, echoed back verbatim on the next request.
    let contentBlocks: [[String: Any]]
    let stopReason: String?
    /// Concatenated text blocks (what the user sees).
    let assistantText: String
    /// Client `tool_use` blocks we must execute (server tools like web_search are excluded).
    let toolUses: [ToolUse]
}

enum CoachError: Error {
    case network
    case http(Int, String)
    case decoding

    var userMessage: String {
        switch self {
        case .network:
            return "Couldn't reach the network. Check your connection and try again."
        case .http(let code, let message):
            if code == 401 { return "Your API key was rejected (401). Check it in Settings → Coach." }
            if code == 429 { return "Rate limited (429). Wait a moment and try again." }
            return "The coach API returned an error (\(code)). \(message)"
        case .decoding:
            return "Got an unexpected response from the coach API."
        }
    }
}

/// Abstraction over the Messages API so the agent loop is testable with a mock.
protocol CoachBackend {
    func send(systemPrompt: String,
              messages: [[String: Any]],
              tools: [[String: Any]],
              model: String) async throws -> AnthropicResponse
}

/// Minimal Anthropic Messages API client (non-streaming, tool-use aware).
final class AnthropicClient: CoachBackend {
    private let apiKey: String
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func send(systemPrompt: String,
              messages: [[String: Any]],
              tools: [[String: Any]],
              model: String) async throws -> AnthropicResponse {

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "system": systemPrompt,
            "messages": messages,
        ]
        if !tools.isEmpty { body["tools"] = tools }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CoachError.network
        }

        guard let http = response as? HTTPURLResponse else { throw CoachError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw CoachError.http(http.statusCode, Self.errorMessage(from: data))
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else {
            throw CoachError.decoding
        }

        let stopReason = object["stop_reason"] as? String
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        let toolUses = content.compactMap { block -> ToolUse? in
            guard (block["type"] as? String) == "tool_use",
                  let id = block["id"] as? String,
                  let name = block["name"] as? String else { return nil }
            return ToolUse(id: id, name: name, input: block["input"] as? [String: Any] ?? [:])
        }

        return AnthropicResponse(contentBlocks: content, stopReason: stopReason,
                                 assistantText: text, toolUses: toolUses)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = obj["error"] as? [String: Any],
              let message = error["message"] as? String else { return "" }
        return message
    }
}
