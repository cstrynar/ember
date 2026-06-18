import SwiftUI
import EmberCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingProfile = false

    var body: some View {
        NavigationStack {
            List {
                Section("You") {
                    Button { showingProfile = true } label: {
                        HStack {
                            Label("Profile & goal", systemImage: "person.crop.circle")
                            Spacer()
                            Text(model.profile.map { $0.goal.title } ?? "Set up")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let goal = model.goal {
                        LabeledContent("Daily target", value: "\(whole(goal.calories)) kcal")
                        LabeledContent("Protein / Carbs / Fat",
                                       value: "\(whole(goal.proteinG)) / \(whole(goal.carbG)) / \(whole(goal.fatG)) g")
                    }
                }

                Section("Reminders") {
                    NavigationLink {
                        ReminderSettingsView().environmentObject(model)
                    } label: {
                        Label("Meal & water reminders", systemImage: "bell")
                    }
                }

                if model.isHealthDataAvailable {
                    Section("Apple Health") {
                        Button { model.requestHealthAccess() } label: {
                            Label("Connect Apple Health", systemImage: "heart.text.square")
                        }
                        Text("Let Ember read your workouts and weight (and steps, energy, resting heart rate, sleep) from Health. Optional — Ember works fully on manual entry if you decline. Ember never writes to Health.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Coach") {
                    NavigationLink {
                        CoachSettingsView().environmentObject(model)
                    } label: {
                        HStack {
                            Label("API key & model", systemImage: "sparkles")
                            Spacer()
                            Text(model.hasAPIKey ? "Ready" : "Set up")
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        CoachNotesView().environmentObject(model)
                    } label: {
                        HStack {
                            Label("Coach notes", systemImage: "doc.text.magnifyingglass")
                            Spacer()
                            if model.isWeeklyReviewDue {
                                Text("Due").foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section {
                    Text("Ember gives general fitness information, not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingProfile) {
                ProfileView().environmentObject(model)
            }
        }
    }
}
