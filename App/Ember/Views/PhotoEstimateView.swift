import SwiftUI
import PhotosUI
import UIKit
import EmberCore

/// Estimate a meal's macros from a photo. Idle offers a library `PhotosPicker` and (when the
/// device has a camera) a capture button; on selection it runs `AppModel.estimateMacros` and
/// shows a loading spinner, then either an editable review of the parsed items or a clear
/// failure with a retry. The review's items are fully editable; Confirm logs each through the
/// existing `AppModel.logManual` path and dismisses.
struct PhotoEstimateView: View {
    @EnvironmentObject var app: AppModel

    /// Called after a successful Confirm to dismiss the Add sheet (same seam as `ManualFoodView`).
    var onDone: () -> Void = {}

    /// The four phases of a single estimate attempt.
    private enum Phase {
        case idle
        case loading
        case review(PhotoMacroResult)
        case failure(String)
    }

    @State private var phase: Phase = .idle
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false

    /// Editable review state, seeded from the parsed result when entering `.review`.
    @State private var rows: [EditableEstimateRow] = []
    @State private var assumptions = ""
    @State private var uncertainty: EstimateUncertainty = .unknown
    @State private var meal: Meal = Meal.suggestedForNow()

    var body: some View {
        Group {
            switch phase {
            case .idle:                  idle
            case .loading:               loading
            case .review(let result):    review(result)
            case .failure(let message):  failure(message)
            }
        }
        .navigationTitle("Estimate from photo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await estimate(image)
                } else {
                    phase = .failure("Couldn't read that photo. Try another.")
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in
                showingCamera = false
                Task { await estimate(image) }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Phases

    @ViewBuilder
    private var idle: some View {
        if !app.hasAPIKey {
            noKey
        } else {
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.largeTitle).foregroundStyle(.orange)
                Text("Estimate macros from a photo")
                    .font(.headline)
                Text("Pick a photo of your meal (or take one) and Ember asks your coach to estimate the macros. Nothing is logged yet — you'll review the estimate first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take a photo", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var noKey: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.orange)
            Text("Add your Anthropic API key").font(.headline)
            Text("In Settings → Coach, paste your key to estimate macros from a photo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loading: some View {
        ProgressView("Estimating…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func review(_ result: PhotoMacroResult) -> some View {
        List {
            Section {
                ForEach($rows) { $row in
                    editRow($row)
                }
                .onDelete { rows.remove(atOffsets: $0) }
            } header: {
                Text("Estimated items")
            } footer: {
                Text("Edit any field, adjust servings, or swipe to delete. Nothing is logged until you tap Log.")
            }

            Section("Notes") {
                if !assumptions.isEmpty {
                    Text(assumptions)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Confidence")
                    Spacer()
                    Text(uncertaintyLabel(uncertainty))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Meal") {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("This adds") {
                MacroSummaryView(consumed: liveTotal, goal: nil)
            }

            Section {
                Button("Log \(rows.count) item\(rows.count == 1 ? "" : "s")") { confirm() }
                    .disabled(!canConfirm)
                Button("Try another photo") { reset() }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// One fully editable estimated item: name + serving + four macro fields + a per-item
    /// servings stepper, mirroring `ManualFoodView`'s field conventions.
    @ViewBuilder
    private func editRow(_ row: Binding<EditableEstimateRow>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: row.name)
            TextField("Serving (optional)", text: row.serving)
                .font(.subheadline).foregroundStyle(.secondary)
            macroField("Calories", text: row.calories, unit: "kcal")
            macroField("Protein", text: row.protein, unit: "g")
            macroField("Carbs", text: row.carb, unit: "g")
            macroField("Fat", text: row.fat, unit: "g")
            Stepper(value: row.servings, in: 0.5...20, step: 0.5) {
                Text("\(formatServings(row.servings.wrappedValue)) serving\(row.servings.wrappedValue == 1 ? "" : "s")")
            }
        }
        .padding(.vertical, 4)
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

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try another photo") { reset() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Flow

    /// The live macro total across all rows, scaled by each row's servings.
    private var liveTotal: Macros {
        rows.reduce(Macros.zero) { $0 + $1.contribution }
    }

    /// Confirm is enabled only with at least one row, all of which have a non-blank name.
    private var canConfirm: Bool {
        !rows.isEmpty && rows.allSatisfy { $0.hasName }
    }

    private func estimate(_ image: UIImage) async {
        phase = .loading
        switch await app.estimateMacros(from: image) {
        case .success(let result):
            rows = result.items.map(EditableEstimateRow.init)
            assumptions = result.assumptions
            uncertainty = result.uncertainty
            meal = Meal.suggestedForNow()
            phase = .review(result)
        case .noKey:
            phase = .failure("Add your Anthropic API key in Settings → Coach.")
        case .encodeFailed:
            phase = .failure("Couldn't read that photo. Try another.")
        case .parseFailed:
            phase = .failure("Couldn't read a food estimate from that photo. Try another.")
        case .requestFailed(let message):
            phase = .failure(message)
        }
    }

    /// Logs each edited row through the existing manual-entry path, then dismisses the sheet.
    private func confirm() {
        for row in rows {
            app.logManual(name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                          macros: row.macros,
                          servings: row.servings,
                          meal: meal,
                          saveToLibrary: false)
        }
        onDone()
    }

    /// Returns to idle and clears the last picker selection so re-picking the same photo fires.
    private func reset() {
        pickerItem = nil
        rows = []
        phase = .idle
    }

    private func uncertaintyLabel(_ u: EstimateUncertainty) -> String {
        switch u {
        case .low:     return "Low"
        case .medium:  return "Medium"
        case .high:    return "High"
        case .unknown: return "Unknown"
        }
    }
}

/// A mutable, identity-stable UI mirror of a parsed `EstimatedFoodItem`, so the review's
/// `ForEach` can bind editable `TextField`s + a stepper and support swipe-to-delete. The
/// parsed `macros` are treated as per-serving (as `PhotoMacroParser` documents).
private struct EditableEstimateRow: Identifiable {
    let id = UUID()
    var name: String
    var serving: String
    var calories: String
    var protein: String
    var carb: String
    var fat: String
    var servings: Double

    init(_ item: EstimatedFoodItem) {
        name = item.name
        serving = item.serving
        calories = whole(item.macros.calories)
        protein = whole(item.macros.proteinG)
        carb = whole(item.macros.carbG)
        fat = whole(item.macros.fatG)
        servings = 1
    }

    var macros: Macros {
        Macros(calories: Double(calories) ?? 0,
               proteinG: Double(protein) ?? 0,
               carbG: Double(carb) ?? 0,
               fatG: Double(fat) ?? 0)
    }

    var contribution: Macros { macros.scaled(by: servings) }

    var hasName: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
