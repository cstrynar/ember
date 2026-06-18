import SwiftUI
import EmberCore

/// Calories + the three macros as labeled progress bars. `goal == nil` shows totals only.
struct MacroSummaryView: View {
    let consumed: Macros
    let goal: Macros?

    var body: some View {
        VStack(spacing: 10) {
            MacroBar(label: "Calories", value: consumed.calories, target: goal?.calories, unit: "kcal", tint: .orange)
            MacroBar(label: "Protein",  value: consumed.proteinG, target: goal?.proteinG, unit: "g", tint: .red)
            MacroBar(label: "Carbs",    value: consumed.carbG,    target: goal?.carbG,    unit: "g", tint: .blue)
            MacroBar(label: "Fat",      value: consumed.fatG,     target: goal?.fatG,     unit: "g", tint: .yellow)
        }
        .padding(.vertical, 4)
    }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let target: Double?
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                if let target {
                    Text("\(whole(value)) / \(whole(target)) \(unit)")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("\(whole(value)) \(unit)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let target, target > 0 {
                ProgressView(value: min(value / target, 1.0)).tint(tint)
            }
        }
    }
}

/// A logged food row: name, serving/macros caption, calories.
struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(whole(entry.consumed.calories)) kcal").foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        let c = entry.consumed
        return "\(formatServings(entry.servings))× · P\(whole(c.proteinG)) C\(whole(c.carbG)) F\(whole(c.fatG))"
    }
}

/// A compact food row for browsing/searching the database: name (+ favorite star),
/// a macro caption, and calories. Denser than a default row so more foods fit on screen.
struct FoodBrowseRow: View {
    let item: FoodItem
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.orange)
                    }
                    Text(item.name).font(.subheadline).lineLimit(1)
                }
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(whole(item.macrosPerServing.calories)) kcal")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }

    private var caption: String {
        let m = item.macrosPerServing
        return "\(item.servingDescription) · P\(whole(m.proteinG)) C\(whole(m.carbG)) F\(whole(m.fatG))"
    }
}

/// A star toggle used wherever a food can be (un)favorited without conflicting with row taps.
struct FavoriteButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .imageScale(.large)
                .foregroundStyle(isOn ? .orange : .secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isOn ? "Remove from favorites" : "Add to favorites")
    }
}

/// A tappable chip in a horizontal quick-add strip (Food or Train). One tap re-logs.
/// `detail` is the caller-formatted secondary line (e.g. "210 kcal" or "5 × 100 kg").
struct QuickAddChip: View {
    let name: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minWidth: 96, maxWidth: 150, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(name)")
    }
}

/// The actionable "what's left today" line: calories (turns red when over) and protein left.
struct RemainingHeader: View {
    let consumed: Macros
    let goal: Macros

    var body: some View {
        let kcalLeft = goal.calories - consumed.calories
        let proteinLeft = max(goal.proteinG - consumed.proteinG, 0)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(whole(abs(kcalLeft))) kcal")
                    .font(.title2.bold())
                    .foregroundStyle(kcalLeft < 0 ? .red : .primary)
                Text(kcalLeft < 0 ? "over budget" : "left today")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(whole(proteinLeft)) g").font(.headline)
                Text("protein left").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Hydration progress + a quick "add a glass" button.
struct HydrationRow: View {
    let ml: Int
    let target: Int
    let onAddGlass: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(ml) / \(target) ml").font(.subheadline)
                ProgressView(value: target > 0 ? min(Double(ml) / Double(target), 1.0) : 0).tint(.blue)
            }
            Button(action: onAddGlass) {
                Label("+\(NutritionDefaults.glassML)", systemImage: "drop.fill")
            }
            .buttonStyle(.bordered)
        }
    }
}
