import SwiftUI
import EmberCore

/// The Food tab: today's macros vs goal, a one-tap quick-add strip, hydration, and meals.
struct FoodView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingAdd = false
    @State private var showingProfile = false
    @State private var undo: UndoToast?

    var body: some View {
        NavigationStack {
            List {
                if !model.hasProfile {
                    Section {
                        Button { showingProfile = true } label: {
                            Label("Set up your profile to get macro targets",
                                  systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }

                Section("Today") {
                    if let goal = model.goal {
                        RemainingHeader(consumed: model.consumed, goal: goal)
                    }
                    MacroSummaryView(consumed: model.consumed, goal: model.goal)
                }

                let quick = model.quickAddItems()
                if !quick.isEmpty {
                    Section("Quick add") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quick) { entry in
                                    QuickAddChip(name: entry.item.name,
                                                 detail: "\(whole(chipKcal(entry))) kcal") {
                                        quickAdd(entry)
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section("Hydration") {
                    HydrationRow(ml: model.hydration.milliliters, target: model.hydrationTargetML) {
                        model.addWater(NutritionDefaults.glassML)
                    }
                }

                ForEach(Meal.allCases, id: \.self) { meal in
                    mealSection(meal)
                }
            }
            .navigationTitle("Food")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add food")
                }
            }
            .sheet(isPresented: $showingAdd) {
                QuickAddView().environmentObject(model)
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView().environmentObject(model)
            }
            .safeAreaInset(edge: .bottom) { undoBanner }
            .animation(.spring(duration: 0.3), value: undo)
        }
    }

    /// Tap a chip: re-log a recent food at its prior servings + meal, else (a favorite with
    /// no history) log one serving at the suggested meal. Either way, offer Undo.
    private func quickAdd(_ entry: QuickAddEntry) {
        let id = entry.recent.map(model.reLog) ?? model.quickLog(entry.item)
        undo = UndoToast(entryID: id, name: entry.item.name)
    }

    /// Calories a chip tap will log: scaled to the prior servings when there's a snapshot,
    /// otherwise the per-serving value (one serving).
    private func chipKcal(_ entry: QuickAddEntry) -> Double {
        let perServing = entry.item.macrosPerServing.calories
        guard let recent = entry.recent else { return perServing }
        return entry.item.macrosPerServing.scaled(by: recent.lastServings).calories
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let toast = undo {
            HStack {
                Text("Logged \(toast.name)").font(.subheadline)
                Spacer()
                Button("Undo") {
                    model.removeEntry(toast.entryID)
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

    @ViewBuilder
    private func mealSection(_ meal: Meal) -> some View {
        let entries = model.today.entries.filter { $0.meal == meal }
        if !entries.isEmpty {
            Section(meal.title) {
                ForEach(entries) { entry in
                    FoodEntryRow(entry: entry)
                }
                .onDelete { offsets in
                    offsets.map { entries[$0].id }.forEach(model.removeEntry)
                }
            }
        }
    }
}

/// Transient "logged X — Undo" state for the quick-add strip.
private struct UndoToast: Identifiable, Equatable {
    let id = UUID()
    let entryID: UUID
    let name: String
}
