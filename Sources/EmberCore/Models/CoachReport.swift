import Foundation

/// A weekly maintenance report produced by the coach (markdown body).
public struct CoachReport: Codable, Equatable, Identifiable {
    /// The day key the report was generated on (one report per day max).
    public let id: String
    public let createdAt: Date
    public let markdown: String

    public init(id: String, createdAt: Date = Date(), markdown: String) {
        self.id = id
        self.createdAt = createdAt
        self.markdown = markdown
    }
}
