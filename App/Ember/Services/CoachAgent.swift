import Foundation
import EmberCore

/// Drives the agentic loop: send the conversation, run any client tools the model asks
/// for, feed results back, and repeat until the model produces a final text answer.
@MainActor
final class CoachAgent {
    private let backend: CoachBackend
    private let tools: CoachTools
    private let model: String
    private let maxIterations = 6

    init(backend: CoachBackend, tools: CoachTools, model: String) {
        self.backend = backend
        self.tools = tools
        self.model = model
    }

    /// Runs to completion. Returns the final assistant text plus the full updated message
    /// history (including tool_use / tool_result turns) to thread into the next request.
    func run(systemPrompt: String,
             messages: [[String: Any]]) async throws -> (reply: String, messages: [[String: Any]]) {
        var conversation = messages
        let toolDefs = tools.definitions()

        for _ in 0..<maxIterations {
            let response = try await backend.send(systemPrompt: systemPrompt,
                                                  messages: conversation,
                                                  tools: toolDefs,
                                                  model: model)
            // Echo the assistant's content back verbatim so tool_use ids line up.
            conversation.append(["role": "assistant", "content": response.contentBlocks])

            if response.toolUses.isEmpty {
                // A paused turn means a server tool (web_search) is mid-flight; resend to resume.
                if response.stopReason == "pause_turn" { continue }
                return (response.assistantText, conversation)
            }

            var results: [[String: Any]] = []
            for use in response.toolUses {
                let output = tools.run(name: use.name, input: use.input)
                results.append(["type": "tool_result", "tool_use_id": use.id, "content": output])
            }
            conversation.append(["role": "user", "content": results])
        }

        return ("I wasn't able to finish that one — could you try rephrasing?", conversation)
    }

    /// Builds the system prompt, folding in the user's profile/goal for context.
    static func systemPrompt(app: AppModel) -> String {
        var lines = [
            "You are Ember, a warm, practical personal health & fitness coach for one person.",
            "Help with nutrition (macros), workouts, hydration, and habits. Be concise and encouraging — never guilt-trippy.",
            "Use the tools to read the user's real data and to log foods, sets, and water, and to adjust reminders. Prefer search_food_database before logging a food by raw macros.",
            "Use web_search for current nutrition/fitness facts when useful, and mention sources briefly.",
            "Units are metric (kg, cm, ml). Today's date key is \(app.dayKey).",
            "You give general fitness information, not medical advice; recommend a professional for medical concerns.",
            "After logging something, confirm what you logged in one short sentence.",
            "Use the remember tool to record durable facts about the user (diet, goals, what's worked, injuries/limits); don't re-record facts already in your saved memory below.",
        ]
        if let p = app.profile, let g = app.goal {
            let currentWeight = app.currentWeightKg ?? p.weightKg
            lines.append("Profile: \(p.sex.rawValue), age \(p.age), \(Int(p.heightCm.rounded())) cm, "
                + "\(Int(currentWeight.rounded())) kg, activity \(p.activity.rawValue), goal \(p.goal.rawValue), "
                + "diet \(p.dietaryPattern.rawValue). Daily target ~\(Int(g.calories.rounded())) kcal "
                + "(P\(Int(g.proteinG.rounded())) C\(Int(g.carbG.rounded())) F\(Int(g.fatG.rounded()))).")
            if let target = p.goalWeightKg {
                lines.append("Target weight ~\(Int(target.rounded())) kg.")
            }
            if !p.notes.isEmpty { lines.append("User notes: \(p.notes)") }
        } else {
            lines.append("The user hasn't set up a profile yet — encourage them to do so in Settings for macro targets.")
        }
        if !app.coachMemory.isEmpty {
            lines.append("Saved memory (durable facts you've recorded about this user):")
            lines.append(contentsOf: app.coachMemory.promptLines())
        }
        return lines.joined(separator: "\n")
    }
}
