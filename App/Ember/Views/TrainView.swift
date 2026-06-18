import SwiftUI
import EmberCore

/// The Train tab: a one-tap quick-add strip, today's logged sets (grouped by exercise),
/// and a link to progress charts.
struct TrainView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingAdd = false
    @State private var undo: UndoSetToast?

    var body: some View {
        NavigationStack {
            List {
                if !model.recentExercises.isEmpty {
                    Section("Quick add") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(model.recentExercises.prefix(8))) { recent in
                                    QuickAddChip(name: recent.name,
                                                 detail: chipDetail(recent)) {
                                        quickAdd(recent)
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                if model.todayWorkout.isEmpty {
                    Section {
                        Text("No sets logged today. Tap + to start your workout.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.todayExerciseGroups) { group in
                        Section(group.name) {
                            ForEach(group.sets) { set in
                                SetRow(set: set)
                            }
                            .onDelete { offsets in
                                offsets.map { group.sets[$0].id }.forEach(model.removeSet)
                            }
                        }
                    }
                    Section {
                        LabeledContent("Total volume", value: "\(whole(model.todayVolume)) kg")
                    }
                }

                if !model.workoutHistory.health.isEmpty {
                    Section("From Apple Health") {
                        ForEach(model.workoutHistory.health) { workout in
                            HealthWorkoutRow(workout: workout)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        ProgressOverviewView().environmentObject(model)
                    } label: {
                        Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                    }
                }
            }
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add set")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddSetView { id, name in
                    undo = UndoSetToast(setID: id, name: name)
                }
                .environmentObject(model)
            }
            .safeAreaInset(edge: .bottom) { undoBanner }
            .animation(.spring(duration: 0.3), value: undo)
        }
    }

    /// Tap a chip: one-tap re-log the recent's last set, then offer Undo.
    private func quickAdd(_ recent: RecentExercise) {
        let id = model.reLogSet(recent)
        undo = UndoSetToast(setID: id, name: recent.name)
    }

    /// The chip's secondary line: the set a tap will log (reps × weight).
    private func chipDetail(_ recent: RecentExercise) -> String {
        "\(recent.lastReps) × \(formatServings(recent.lastWeightKg)) kg"
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let toast = undo {
            HStack {
                Text("Logged \(toast.name)").font(.subheadline)
                Spacer()
                Button("Undo") {
                    model.removeSet(toast.setID)
                    undo = nil
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.quaternary))
            .padding(.horizontal)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if undo?.id == toast.id { undo = nil }
            }
        }
    }
}

/// Transient "logged X — Undo" state for a one-tap workout re-log.
private struct UndoSetToast: Identifiable, Equatable {
    let id = UUID()
    let setID: UUID
    let name: String
}

struct SetRow: View {
    let set: LoggedSet
    var body: some View {
        HStack {
            Text("\(set.reps) × \(formatServings(set.weightKg)) kg")
            Spacer()
            Text("1RM ~\(whole(WorkoutProgress.estimatedOneRepMax(set))) kg")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A read-only Apple-Health-sourced workout summary (device data — no edit/delete).
struct HealthWorkoutRow: View {
    let workout: HealthWorkout

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.kind)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        var parts = ["\(Self.dateFormatter.string(from: workout.date))",
                     "\(whole(workout.durationMin)) min"]
        if let kcal = workout.activeEnergyKcal { parts.append("\(whole(kcal)) kcal") }
        return parts.joined(separator: " · ")
    }
}

/// Pick an exercise (or create a custom one), then enter a set.
struct AddSetView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// When set, present `SetEntryView` prefilled to change a recent's reps/weight ("Edit").
    @State private var editing: EditSetTarget?
    /// Called after a one-tap Recent re-log so the Train root can surface Undo post-dismiss.
    var onReLog: (UUID, String) -> Void = { _, _ in }

    private var results: [Exercise] { ExerciseCatalog.search(query, in: model.exerciseCatalog) }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasExactMatch: Bool {
        let q = trimmedQuery.lowercased()
        return model.exerciseCatalog.contains { $0.name.lowercased() == q }
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty && !model.recentExercises.isEmpty {
                    Section("Recent") {
                        ForEach(Array(model.recentExercises.prefix(8))) { recentRow($0) }
                    }
                }
                if !trimmedQuery.isEmpty && !hasExactMatch {
                    NavigationLink {
                        SetEntryView(exercise: model.makeCustomExercise(named: trimmedQuery)) { dismiss() }
                    } label: {
                        Label("Add “\(trimmedQuery)” as a new exercise", systemImage: "plus")
                    }
                }
                ForEach(results) { exercise in
                    NavigationLink {
                        SetEntryView(exercise: exercise) { dismiss() }
                    } label: {
                        Text(exercise.name)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add set")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { target in
                NavigationStack {
                    SetEntryView(exercise: target.exercise,
                                 initialReps: target.reps,
                                 initialWeightKg: target.weightKg) { dismiss() }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { editing = nil }
                            }
                        }
                }
                .environmentObject(model)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// A one-tap re-log row: the primary tap logs the recent's last set (snapshot reps +
    /// weight) and dismisses; a swipe "Edit" opens `SetEntryView` prefilled to change them.
    @ViewBuilder
    private func recentRow(_ recent: RecentExercise) -> some View {
        Button {
            let id = model.reLogSet(recent)
            onReLog(id, recent.name)
            dismiss()
        } label: {
            HStack {
                Text(recent.name)
                Spacer()
                Text("\(recent.lastReps) × \(formatServings(recent.lastWeightKg)) kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                editing = EditSetTarget(exercise: model.exercise(for: recent),
                                        reps: recent.lastReps, weightKg: recent.lastWeightKg)
            } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .tint(.blue)
        }
    }
}

/// The exercise + prefill snapshot shown when the user taps a Recent row's "Edit" swipe.
private struct EditSetTarget: Identifiable {
    let exercise: Exercise
    let reps: Int
    let weightKg: Double
    var id: String { exercise.id }
}

/// Enter reps + weight for a chosen exercise and log the set.
struct SetEntryView: View {
    @EnvironmentObject var model: AppModel
    let exercise: Exercise
    /// Optional explicit prefill (the Edit path passes the recent snapshot); when nil, the
    /// existing `lastSet` lookup prefills the field.
    var initialReps: Int? = nil
    var initialWeightKg: Double? = nil
    var onDone: () -> Void

    @State private var reps = ""
    @State private var weight = ""

    private var isValid: Bool { (Int(reps) ?? 0) > 0 }

    var body: some View {
        Form {
            Section { Text(exercise.name).font(.headline) }
            Section("Set") {
                field("Reps", text: $reps, unit: "reps", keyboard: .numberPad)
                field("Weight", text: $weight, unit: "kg", keyboard: .decimalPad)
            }
            Section {
                Button("Log set") {
                    model.logSet(exercise: exercise, reps: Int(reps) ?? 0, weightKg: Double(weight) ?? 0)
                    onDone()
                }
                .disabled(!isValid)
            }
        }
        .navigationTitle("Log set")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard reps.isEmpty, weight.isEmpty else { return }
        if let initialReps, let initialWeightKg {
            reps = String(initialReps)
            weight = formatServings(initialWeightKg)
            return
        }
        guard let last = model.lastSet(forExerciseID: exercise.id) else { return }
        reps = String(last.reps)
        weight = formatServings(last.weightKg)
    }

    private func field(_ label: String, text: Binding<String>, unit: String,
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
}
