import Foundation

/// A single durable fact the coach has recorded about the user (diet, goals, what's worked,
/// injuries/limits). Persists across conversations and is folded into the coach's system prompt.
public struct CoachMemoryItem: Codable, Equatable, Identifiable {
    public let id: UUID
    /// A free-text grouping (e.g. "diet", "goals", "injuries"); `"general"` when unspecified.
    public var category: String
    public var text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), category: String = "general", text: String,
                createdAt: Date = Date()) {
        self.id = id
        self.category = category
        self.text = text
        self.createdAt = createdAt
    }
}

/// The coach's durable memory: an ordered list of facts about the user. Pure value type;
/// mutating helpers return new values (matching `DayNutrition`'s immutable-ish style).
public struct CoachMemory: Codable, Equatable {
    public var items: [CoachMemoryItem]

    public init(items: [CoachMemoryItem] = []) {
        self.items = items
    }

    /// An empty memory, used as the default when nothing has been stored.
    public static let empty = CoachMemory()

    /// A soft cap on how many facts to keep so the system prompt can't grow unbounded.
    public static let defaultMax = 40

    public var isEmpty: Bool { items.isEmpty }

    /// Appends a new fact (newest goes last).
    public func adding(category: String = "general", text: String) -> CoachMemory {
        CoachMemory(items: items + [CoachMemoryItem(category: category, text: text)])
    }

    /// Updates the targeted fact's category and/or text. No-ops on an unknown id.
    public func updating(id: UUID, category: String? = nil, text: String? = nil) -> CoachMemory {
        CoachMemory(items: items.map { item in
            guard item.id == id else { return item }
            var updated = item
            if let category { updated.category = category }
            if let text { updated.text = text }
            return updated
        })
    }

    /// Drops the targeted fact. No-ops on an unknown id.
    public func removing(id: UUID) -> CoachMemory {
        CoachMemory(items: items.filter { $0.id != id })
    }

    /// Keeps the most-recent `max` facts (by position; newest is last).
    public func capped(to max: Int = CoachMemory.defaultMax) -> CoachMemory {
        guard items.count > max, max >= 0 else { return self }
        return CoachMemory(items: Array(items.suffix(max)))
    }

    /// Deterministic bulleted lines for the system prompt, in stored (newest-last) order.
    /// Renders `- [injuries] left knee — avoid deep squats`; the bracket is omitted for
    /// the `"general"` category.
    public func promptLines() -> [String] {
        items.map { item in
            let trimmed = item.category.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.lowercased() == "general" {
                return "- \(item.text)"
            }
            return "- [\(trimmed)] \(item.text)"
        }
    }
}
