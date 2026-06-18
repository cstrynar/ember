import SwiftUI
import Charts
import EmberCore

/// Lists exercises with logged history; tap through to per-exercise charts.
struct ProgressOverviewView: View {
    @EnvironmentObject var model: AppModel

    private var exercises: [WorkoutProgress.ExerciseRef] {
        WorkoutProgress.distinctExercises(in: model.allWorkouts)
    }

    var body: some View {
        List {
            if exercises.isEmpty {
                Text("Log a few workouts to see progress here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(exercises) { ref in
                    NavigationLink {
                        ExerciseProgressView(ref: ref).environmentObject(model)
                    } label: {
                        Text(ref.name)
                    }
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Estimated-1RM and volume trends for a single exercise.
struct ExerciseProgressView: View {
    @EnvironmentObject var model: AppModel
    let ref: WorkoutProgress.ExerciseRef

    private var oneRepMax: [WorkoutProgress.Point] {
        WorkoutProgress.oneRepMaxHistory(exerciseID: ref.id, in: model.allWorkouts)
    }
    private var volume: [WorkoutProgress.Point] {
        WorkoutProgress.volumeHistory(exerciseID: ref.id, in: model.allWorkouts)
    }

    var body: some View {
        List {
            Section("Estimated 1RM (kg)") { chart(oneRepMax, tint: .orange) }
            Section("Volume (kg)") { chart(volume, tint: .blue) }
        }
        .navigationTitle(ref.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func chart(_ points: [WorkoutProgress.Point], tint: Color) -> some View {
        if points.count < 2 {
            Text(points.isEmpty ? "No data yet." : "Log more sessions to see a trend.")
                .foregroundStyle(.secondary)
        } else {
            Chart(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(tint)
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(tint)
            }
            .frame(height: 180)
        }
    }
}
