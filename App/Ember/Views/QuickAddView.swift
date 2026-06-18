import SwiftUI
import EmberCore

/// Low-friction food logging: search the database, or add a custom food.
struct QuickAddView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// When set, push `LogFoodView` to change servings/meal for this food ("Edit" path).
    @State private var editing: EditTarget?

    private var results: [FoodItem] { model.foodDatabase.search(query) }

    /// Recents as loggable items, minus anything already pinned under Favorites.
    private var recentItems: [FoodItem] {
        let favIDs = Set(model.favoriteFoodIDs)
        return model.recents.map { model.foodItem(for: $0) }.filter { !favIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        NavigationLink {
                            ManualFoodView(initialName: "") { dismiss() }
                        } label: {
                            Label("Add a custom food", systemImage: "square.and.pencil")
                        }
                        NavigationLink {
                            PhotoEstimateView(onDone: { dismiss() })
                        } label: {
                            Label("Estimate from photo", systemImage: "camera.viewfinder")
                        }
                    }
                    if !model.favoriteFoods.isEmpty {
                        Section("Favorites") {
                            ForEach(model.favoriteFoods) { quickRow($0) }
                        }
                    }
                    if !recentItems.isEmpty {
                        Section("Recent") {
                            ForEach(recentItems) { quickRow($0) }
                        }
                    }
                    Section("All foods (\(model.allFoods.count))") {
                        ForEach(model.allFoods) { foodLink($0) }
                    }
                } else {
                    ForEach(results) { foodLink($0) }
                    if results.isEmpty {
                        NavigationLink {
                            ManualFoodView(initialName: query) { dismiss() }
                        } label: {
                            Label("No match — add “\(query)” as a custom food", systemImage: "plus")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search foods")
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { target in
                NavigationStack {
                    LogFoodView(item: target.item,
                                initialServings: target.servings,
                                initialMeal: target.meal) { dismiss() }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { editing = nil }
                            }
                        }
                }
                .environmentObject(model)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// A one-tap re-log row (Favorites / Recent): the primary tap logs immediately at the
    /// food's prior servings + meal (or 1 serving for a never-logged favorite), then the
    /// sheet dismisses. A swipe "Edit" opens `LogFoodView` prefilled for different servings;
    /// the favorite/unfavorite swipe is preserved.
    @ViewBuilder
    private func quickRow(_ item: FoodItem) -> some View {
        let recent = model.recent(forID: item.id)
        Button {
            if let recent { model.reLog(recent) } else { model.quickLog(item) }
            dismiss()
        } label: {
            FoodBrowseRow(item: item, isFavorite: model.isFavorite(item.id))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                editing = EditTarget(item: item,
                                     servings: recent?.lastServings ?? 1,
                                     meal: recent?.lastMeal ?? Meal.suggestedForNow())
            } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            favoriteSwipe(item)
        }
    }

    /// A browsable food row (All foods / search): tap to set servings/meal; swipe to
    /// (un)favorite. Prefills from a matching recent snapshot when the food has history.
    @ViewBuilder
    private func foodLink(_ item: FoodItem) -> some View {
        let recent = model.recent(forID: item.id)
        NavigationLink {
            LogFoodView(item: item,
                        initialServings: recent?.lastServings ?? 1,
                        initialMeal: recent?.lastMeal ?? Meal.suggestedForNow()) { dismiss() }
        } label: {
            FoodBrowseRow(item: item, isFavorite: model.isFavorite(item.id))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            favoriteSwipe(item)
        }
    }

    @ViewBuilder
    private func favoriteSwipe(_ item: FoodItem) -> some View {
        let fav = model.isFavorite(item.id)
        Button { model.setFavorite(item, !fav) } label: {
            Label(fav ? "Unfavorite" : "Favorite",
                  systemImage: fav ? "star.slash" : "star")
        }
        .tint(.orange)
    }
}

/// The food + prefill snapshot shown when the user taps a row's "Edit" swipe action.
private struct EditTarget: Identifiable {
    let item: FoodItem
    let servings: Double
    let meal: Meal
    var id: String { item.id }
}

/// Choose servings + meal for a known food, then log it.
struct LogFoodView: View {
    @EnvironmentObject var model: AppModel
    let item: FoodItem
    var initialServings: Double = 1
    var initialMeal: Meal = Meal.suggestedForNow()
    var onDone: () -> Void

    @State private var servings: Double = 1
    @State private var meal: Meal = Meal.suggestedForNow()
    @State private var didPrefill = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.headline)
                        Text(item.servingDescription).foregroundStyle(.secondary)
                    }
                    Spacer()
                    FavoriteButton(isOn: model.isFavorite(item.id)) { model.toggleFavorite(item) }
                }
            }
            Section("Servings") {
                Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                    Text("\(formatServings(servings)) serving\(servings == 1 ? "" : "s")")
                }
            }
            Section("Meal") {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("This adds") {
                MacroSummaryView(consumed: item.macrosPerServing.scaled(by: servings), goal: nil)
            }
            Section {
                Button("Log it") {
                    model.log(item, servings: servings, meal: meal)
                    onDone()
                }
            }
        }
        .navigationTitle("Log food")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !didPrefill {
                servings = initialServings
                meal = initialMeal
                didPrefill = true
            }
        }
    }
}

/// Enter a food by hand; optionally save it to the user's food library.
struct ManualFoodView: View {
    @EnvironmentObject var model: AppModel
    let initialName: String
    var onDone: () -> Void

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var servings: Double = 1
    @State private var meal: Meal = Meal.suggestedForNow()
    @State private var saveToLibrary = true

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section("Food") {
                TextField("Name", text: $name)
            }
            Section("Macros per serving") {
                macroField("Calories", text: $calories, unit: "kcal")
                macroField("Protein", text: $protein, unit: "g")
                macroField("Carbs", text: $carbs, unit: "g")
                macroField("Fat", text: $fat, unit: "g")
            }
            Section("Servings") {
                Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                    Text("\(formatServings(servings)) serving\(servings == 1 ? "" : "s")")
                }
            }
            Section("Meal") {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Save to my foods", isOn: $saveToLibrary)
            }
            Section {
                Button("Log it") { logIt() }
                    .disabled(trimmedName.isEmpty)
            }
        }
        .navigationTitle("Custom food")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if name.isEmpty { name = initialName } }
    }

    private func macroField(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func logIt() {
        let macros = Macros(calories: Double(calories) ?? 0,
                            proteinG: Double(protein) ?? 0,
                            carbG: Double(carbs) ?? 0,
                            fatG: Double(fat) ?? 0)
        model.logManual(name: trimmedName, macros: macros, servings: servings,
                        meal: meal, saveToLibrary: saveToLibrary)
        onDone()
    }
}
