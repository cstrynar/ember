import Foundation

/// A note the coach records when something felt clunky or some data was missing.
/// Reviewed (and cleared) during the weekly review.
public struct FrictionEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let context: String
    public let note: String

    public init(id: UUID = UUID(), date: Date = Date(), context: String, note: String) {
        self.id = id
        self.date = date
        self.context = context
        self.note = note
    }
}
