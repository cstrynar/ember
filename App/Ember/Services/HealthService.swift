import Foundation
import EmberCore
#if canImport(HealthKit)
import HealthKit
#endif

/// Read-only access to Apple Health, behind a tiny injectable seam.
///
/// Design (mirrors `NotificationService`):
/// - Read-only, local-only, no network egress. The app reads from HealthKit on device;
///   nothing is written to Health and nothing leaves the device.
/// - Permission is requested lazily and non-blockingly. The app is fully usable if denied —
///   the user just falls back to data they enter manually.
/// - The completion `Bool` means "the request flow completed without throwing", NOT
///   "the user granted access". HealthKit deliberately hides read-authorization status
///   (`authorizationStatus` only reports share/write intent), so this stage never claims to
///   know whether a read grant was given.
/// - No HealthKit types appear in this protocol's signature, so the seam is importable
///   everywhere (previews, non-iOS hosts) and `HealthKitAccess` is the only HealthKit importer.
protocol HealthAccess {
    /// Whether Health data is available on this device (false on iPad / hosts without Health).
    var isHealthDataAvailable: Bool { get }
    /// Requests read authorization for Ember's v1 Health types. Non-blocking; never throws to
    /// the caller. `completion` runs on the main actor with whether the flow finished.
    func requestAuthorization(completion: @escaping (Bool) -> Void)

    /// Reads recent body-mass samples (last `daysBack` days). Mapped to EmberCore value
    /// types so no HealthKit type leaks. `completion` runs on the main actor; any error,
    /// denial, no-data, or unavailability yields `[]` (same no-op-on-deny guarantee as auth).
    func recentBodyMass(daysBack: Int, completion: @escaping ([HealthWeightSample]) -> Void)

    /// Reads recent workout summaries (last `daysBack` days). Mapped to EmberCore value
    /// types so no HealthKit type leaks. `completion` runs on the main actor; any error,
    /// denial, no-data, or unavailability yields `[]`.
    func recentWorkouts(daysBack: Int, completion: @escaping ([HealthWorkout]) -> Void)
}

/// The real HealthKit-backed implementation — the only file in the repo that imports HealthKit.
@MainActor
final class HealthKitAccess: HealthAccess {

    #if canImport(HealthKit)
    private let store = HKHealthStore()

    /// Ember's v1 read set: workouts, body mass, active energy, step count, resting heart rate,
    /// and sleep analysis. No write set — Ember never writes to Health.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(activeEnergy) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let restingHR = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(restingHR) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
    }

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard isHealthDataAvailable else { completion(false); return }
        store.requestAuthorization(toShare: [], read: readTypes) { success, _ in
            // `success` is the SDK's "request flow finished" flag, not a grant. Any error is
            // swallowed: the app remains fully usable on manual data either way.
            Task { @MainActor in completion(success) }
        }
    }

    func recentBodyMass(daysBack: Int, completion: @escaping ([HealthWeightSample]) -> Void) {
        guard isHealthDataAvailable,
              let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            completion([]); return
        }
        let predicate = Self.recentPredicate(daysBack: daysBack)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let kg = HKUnit.gramUnit(with: .kilo)
            let mapped: [HealthWeightSample] = (samples as? [HKQuantitySample] ?? []).map {
                HealthWeightSample(date: $0.startDate, weightKg: $0.quantity.doubleValue(for: kg))
            }
            Task { @MainActor in completion(mapped) }
        }
        store.execute(query)
    }

    func recentWorkouts(daysBack: Int, completion: @escaping ([HealthWorkout]) -> Void) {
        guard isHealthDataAvailable else { completion([]); return }
        let predicate = Self.recentPredicate(daysBack: daysBack)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let kcalUnit = HKUnit.kilocalorie()
            let mapped: [HealthWorkout] = (samples as? [HKWorkout] ?? []).map { w in
                let energy = w.totalEnergyBurned?.doubleValue(for: kcalUnit)
                return HealthWorkout(id: w.uuid.uuidString,
                                     dayKey: DayKey.key(for: w.startDate),
                                     date: w.startDate,
                                     kind: Self.activityName(w.workoutActivityType),
                                     durationMin: w.duration / 60,
                                     activeEnergyKcal: energy)
            }
            Task { @MainActor in completion(mapped) }
        }
        store.execute(query)
    }

    /// A predicate for samples started within the last `daysBack` days (open-ended at the top).
    private static func recentPredicate(daysBack: Int) -> NSPredicate {
        let start = Calendar.current.date(byAdding: .day, value: -max(0, daysBack), to: Date())
        return HKQuery.predicateForSamples(withStart: start, end: nil)
    }

    /// A human-readable name for a workout activity type (best-effort; common types named,
    /// others fall back to a generic label so the row is never empty).
    private static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining:  return "Functional Strength Training"
        case .running:                     return "Running"
        case .walking:                     return "Walking"
        case .cycling:                     return "Cycling"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining:                return "Core Training"
        case .yoga:                        return "Yoga"
        case .swimming:                    return "Swimming"
        case .rowing:                      return "Rowing"
        case .elliptical:                  return "Elliptical"
        case .hiking:                      return "Hiking"
        default:                           return "Workout"
        }
    }
    #else
    var isHealthDataAvailable: Bool { false }

    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(false) }
    func recentBodyMass(daysBack: Int, completion: @escaping ([HealthWeightSample]) -> Void) { completion([]) }
    func recentWorkouts(daysBack: Int, completion: @escaping ([HealthWorkout]) -> Void) { completion([]) }
    #endif
}

/// A no-op conformer for SwiftUI previews and hosts without HealthKit. Reports Health as
/// unavailable and never shows a system sheet.
@MainActor
final class NoopHealthAccess: HealthAccess {
    var isHealthDataAvailable: Bool { false }

    func requestAuthorization(completion: @escaping (Bool) -> Void) { completion(false) }
    func recentBodyMass(daysBack: Int, completion: @escaping ([HealthWeightSample]) -> Void) { completion([]) }
    func recentWorkouts(daysBack: Int, completion: @escaping ([HealthWorkout]) -> Void) { completion([]) }
}
