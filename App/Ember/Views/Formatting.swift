import Foundation
import EmberCore

// Display helpers for EmberCore value types. Kept in the App layer so EmberCore stays
// presentation-free.

extension Meal {
    var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        }
    }

    /// A reasonable default meal based on the current time of day.
    static func suggestedForNow(_ date: Date = Date(), calendar: Calendar = .current) -> Meal {
        switch calendar.component(.hour, from: date) {
        case 5..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default:      return .snack
        }
    }
}

extension BiologicalSex {
    var title: String { self == .male ? "Male" : "Female" }
}

extension ActivityLevel {
    var title: String {
        switch self {
        case .sedentary:  return "Sedentary"
        case .light:      return "Lightly active"
        case .moderate:   return "Moderately active"
        case .active:     return "Active"
        case .veryActive: return "Very active"
        }
    }
}

extension Goal {
    var title: String {
        switch self {
        case .lose:     return "Lose"
        case .maintain: return "Maintain"
        case .gain:     return "Gain"
        }
    }
}

extension DietaryPattern {
    var title: String {
        switch self {
        case .balanced:    return "Balanced"
        case .highProtein: return "High protein"
        case .lowCarb:     return "Low carb"
        case .keto:        return "Keto"
        }
    }
}

/// Formats a serving count without a trailing ".0" (e.g. 1, 1.5, 2).
func formatServings(_ s: Double) -> String {
    s == s.rounded() ? String(Int(s)) : String(format: "%.1f", s)
}

/// Rounds a macro/calorie value to a whole-number string.
func whole(_ value: Double) -> String { String(Int(value.rounded())) }
