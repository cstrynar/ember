import Foundation

public enum FoodSource: String, Codable, Equatable {
    case preloaded, custom
}

/// A food the user can log, with macros for one serving.
public struct FoodItem: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var servingDescription: String
    public var macrosPerServing: Macros
    public var source: FoodSource

    public init(id: String, name: String, servingDescription: String,
                macrosPerServing: Macros, source: FoodSource) {
        self.id = id
        self.name = name
        self.servingDescription = servingDescription
        self.macrosPerServing = macrosPerServing
        self.source = source
    }
}
