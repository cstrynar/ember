import SwiftUI
import EmberCore

/// Profile & goal setup. Doubles as onboarding (first run) and edit.
struct ProfileView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var sex: BiologicalSex = .male
    @State private var age = ""
    @State private var height = ""   // cm
    @State private var weight = ""   // kg
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: Goal = .maintain
    @State private var pattern: DietaryPattern = .balanced
    @State private var goalWeight = ""   // kg, optional
    @State private var notes = ""

    private var builtProfile: UserProfile? {
        guard let a = Int(age), a > 0,
              let h = Double(height), h > 0,
              let w = Double(weight), w > 0 else { return nil }
        // Optional: empty or non-positive target weight stays nil and never blocks Save.
        let target = Double(goalWeight).flatMap { $0 > 0 ? $0 : nil }
        return UserProfile(sex: sex, age: a, heightCm: h, weightKg: w,
                           activity: activity, goal: goal, dietaryPattern: pattern,
                           notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                           goalWeightKg: target)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    Picker("Sex", selection: $sex) {
                        ForEach(BiologicalSex.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    numberRow("Age", text: $age, unit: "yrs", keyboard: .numberPad)
                    numberRow("Height", text: $height, unit: "cm", keyboard: .decimalPad)
                    numberRow("Weight", text: $weight, unit: "kg", keyboard: .decimalPad)
                    Picker("Activity", selection: $activity) {
                        ForEach(ActivityLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }

                Section("Goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(Goal.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Diet", selection: $pattern) {
                        ForEach(DietaryPattern.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    numberRow("Target weight", text: $goalWeight, unit: "kg", keyboard: .decimalPad)
                }

                Section("Notes for your coach") {
                    TextField("Allergies, preferences, anything…", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let p = builtProfile {
                    Section("Your daily targets") {
                        MacroSummaryView(consumed: .zero, goal: MacroMath.recommendedGoal(profile: p))
                    }
                }

                Section {
                    Button("Save") { save() }
                        .disabled(builtProfile == nil)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func numberRow(_ label: String, text: Binding<String>, unit: String,
                           keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func loadExisting() {
        guard let p = model.profile else { return }
        sex = p.sex
        age = String(p.age)
        height = formatServings(p.heightCm)
        weight = formatServings(p.weightKg)
        activity = p.activity
        goal = p.goal
        pattern = p.dietaryPattern
        goalWeight = p.goalWeightKg.map(formatServings) ?? ""
        notes = p.notes
    }

    private func save() {
        guard let p = builtProfile else { return }
        model.saveProfile(p)
        // A fresh profile recommendation replaces any stale override.
        model.setGoalOverride(nil)
        dismiss()
    }
}
