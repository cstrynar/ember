import Foundation

public enum BiologicalSex: String, Codable, Equatable, CaseIterable {
    case male, female
}

/// Activity multiplier applied to BMR to estimate total daily energy expenditure.
public enum ActivityLevel: String, Codable, Equatable, CaseIterable {
    case sedentary, light, moderate, active, veryActive

    /// Standard Mifflin–St Jeor activity multipliers.
    public var multiplier: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }
}

public enum Goal: String, Codable, Equatable, CaseIterable {
    case lose, maintain, gain
}

/// Eating pattern that drives the macro split. Restrictions (vegetarian, allergies, …)
/// belong in `notes`, which the coach reads when making recommendations.
public enum DietaryPattern: String, Codable, Equatable, CaseIterable {
    case balanced, highProtein, lowCarb, keto
}

/// Everything needed to compute macro targets, plus free-text notes for the coach.
public struct UserProfile: Codable, Equatable {
    public var sex: BiologicalSex
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var activity: ActivityLevel
    public var goal: Goal
    public var dietaryPattern: DietaryPattern
    public var notes: String
    /// Optional target body weight (kg). Coaching context only — not used by `MacroMath`.
    /// A `nil` default keeps pre-existing saved profiles decodable via synthesized `Codable`.
    public var goalWeightKg: Double?

    public init(sex: BiologicalSex, age: Int, heightCm: Double, weightKg: Double,
                activity: ActivityLevel, goal: Goal, dietaryPattern: DietaryPattern,
                notes: String = "", goalWeightKg: Double? = nil) {
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activity = activity
        self.goal = goal
        self.dietaryPattern = dietaryPattern
        self.notes = notes
        self.goalWeightKg = goalWeightKg
    }
}
