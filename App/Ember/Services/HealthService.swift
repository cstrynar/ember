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

    /// Reads recent active-energy samples (last `daysBack` days), each `value` in kilocalories.
    /// Mapped to EmberCore value types. `completion` on the main actor; error/denial/no-data → `[]`.
    func recentActiveEnergy(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent step-count samples (last `daysBack` days), each `value` a step count.
    /// Mapped to EmberCore value types. `completion` on the main actor; error/denial/no-data → `[]`.
    func recentSteps(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent resting-heart-rate samples (last `daysBack` days), each `value` in bpm.
    /// Mapped to EmberCore value types. `completion` on the main actor; error/denial/no-data → `[]`.
    func recentRestingHeartRate(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent sleep samples (last `daysBack` days). Only "asleep" segments are kept, each
    /// mapped to a sample whose `value` is the segment's duration in minutes, keyed by its start
    /// date. EmberCore rolls these into per-night totals. `completion` on the main actor;
    /// error/denial/no-data → `[]`.
    func recentSleep(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent walking/running distance samples (last `daysBack` days), each `value` in
    /// kilometers. Mapped to EmberCore value types. `completion` on the main actor;
    /// error/denial/no-data → `[]`.
    func recentDistance(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent heart-rate-variability (SDNN) samples (last `daysBack` days), each `value`
    /// in milliseconds. Mapped to EmberCore value types. `completion` on the main actor;
    /// error/denial/no-data → `[]`.
    func recentHRV(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent VO₂max samples (last `daysBack` days), each `value` in mL·kg⁻¹·min⁻¹.
    /// Mapped to EmberCore value types. `completion` on the main actor; error/denial/no-data → `[]`.
    func recentVO2Max(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent heart-rate samples (last `daysBack` days), each `value` in bpm. Used for an
    /// active heart-rate range/average. Mapped to EmberCore value types. `completion` on the
    /// main actor; error/denial/no-data → `[]`.
    func recentHeartRate(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent blood-oxygen (SpO₂) samples (last `daysBack` days), each `value` a percentage
    /// (the 0…1 saturation fraction × 100). Mapped to EmberCore value types. `completion` on the
    /// main actor; error/denial/no-data → `[]`.
    func recentBloodOxygen(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)

    /// Reads recent mindful-session samples (last `daysBack` days), each mapped to a sample whose
    /// `value` is the session's duration in minutes, keyed by its start date. EmberCore rolls
    /// these into per-day totals. `completion` on the main actor; error/denial/no-data → `[]`.
    func recentMindfulMinutes(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void)
}

/// The real HealthKit-backed implementation — the only file in the repo that imports HealthKit.
@MainActor
final class HealthKitAccess: HealthAccess {

    #if canImport(HealthKit)
    private let store = HKHealthStore()

    /// Ember's read set (twelve types): workouts, body mass, active energy, step count, resting
    /// heart rate, sleep analysis, walking/running distance, HRV (SDNN), VO₂max, heart rate,
    /// blood oxygen, and mindful sessions. No write set — Ember never writes to Health.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(activeEnergy) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let restingHR = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(restingHR) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let vo2Max = HKObjectType.quantityType(forIdentifier: .vo2Max) { types.insert(vo2Max) }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        if let bloodOxygen = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) { types.insert(bloodOxygen) }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { types.insert(mindful) }
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

    func recentActiveEnergy(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        quantitySamples(identifier: .activeEnergyBurned, unit: .kilocalorie(),
                        daysBack: daysBack, completion: completion)
    }

    func recentSteps(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        quantitySamples(identifier: .stepCount, unit: .count(),
                        daysBack: daysBack, completion: completion)
    }

    func recentRestingHeartRate(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        quantitySamples(identifier: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()),
                        daysBack: daysBack, completion: completion)
    }

    func recentSleep(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        guard isHealthDataAvailable,
              let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion([]); return
        }
        let predicate = Self.recentPredicate(daysBack: daysBack)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
            let mapped: [HealthQuantitySample] = (samples as? [HKCategorySample] ?? [])
                .filter { asleep.contains($0.value) }
                .map { HealthQuantitySample(date: $0.startDate,
                                            value: $0.endDate.timeIntervalSince($0.startDate) / 60) }
            Task { @MainActor in completion(mapped) }
        }
        store.execute(query)
    }

    func recentDistance(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        // Meters → km at map time so EmberCore receives km.
        quantitySamples(identifier: .distanceWalkingRunning, unit: .meter(),
                        daysBack: daysBack, scale: 1.0 / 1000.0, completion: completion)
    }

    func recentHRV(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        quantitySamples(identifier: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli),
                        daysBack: daysBack, completion: completion)
    }

    func recentVO2Max(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        quantitySamples(identifier: .vo2Max, unit: HKUnit(from: "ml/kg*min"),
                        daysBack: daysBack, completion: completion)
    }

    func recentHeartRate(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        quantitySamples(identifier: .heartRate, unit: HKUnit.count().unitDivided(by: .minute()),
                        daysBack: daysBack, completion: completion)
    }

    func recentBloodOxygen(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        // `HKUnit.percent()` is documented as the 0.0–1.0 range (Apple's `HKUnit.h`:
        // `percentUnit; // % (0.0 - 1.0)`), so `doubleValue(for: .percent())` returns the
        // saturation as a 0…1 fraction (e.g. 0.97), NOT a 0–100 percent. The ×100 here is the
        // single conversion that turns that into a human "%" (97). Verified against Apple's
        // documented unit semantics, not changed — auditable so this isn't re-flagged.
        quantitySamples(identifier: .oxygenSaturation, unit: .percent(),
                        daysBack: daysBack, scale: 100, completion: completion)
    }

    func recentMindfulMinutes(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) {
        // Category type; every mindful session counts (no sub-value filter, unlike sleep).
        guard isHealthDataAvailable,
              let type = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
            completion([]); return
        }
        let predicate = Self.recentPredicate(daysBack: daysBack)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let mapped: [HealthQuantitySample] = (samples as? [HKCategorySample] ?? [])
                .map { HealthQuantitySample(date: $0.startDate,
                                            value: $0.endDate.timeIntervalSince($0.startDate) / 60) }
            Task { @MainActor in completion(mapped) }
        }
        store.execute(query)
    }

    /// Shared `HKQuantitySample` reader: maps each sample's `quantity` (in `unit`, then × `scale`)
    /// to a `HealthQuantitySample` keyed by its start date, newest-first. `scale` lets a caller
    /// convert at map time (e.g. meters → km, the 0…1 SpO₂ fraction → a %) so EmberCore stays
    /// unit-agnostic. Any error/empty/nil/unavailable → `[]` on the main actor (mirrors `recentBodyMass`).
    private func quantitySamples(identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                                 daysBack: Int, scale: Double = 1,
                                 completion: @escaping ([HealthQuantitySample]) -> Void) {
        guard isHealthDataAvailable,
              let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion([]); return
        }
        let predicate = Self.recentPredicate(daysBack: daysBack)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let mapped: [HealthQuantitySample] = (samples as? [HKQuantitySample] ?? []).map {
                HealthQuantitySample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit) * scale)
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
    func recentActiveEnergy(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentSteps(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentRestingHeartRate(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentSleep(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentDistance(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentHRV(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentVO2Max(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentHeartRate(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentBloodOxygen(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentMindfulMinutes(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
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
    func recentActiveEnergy(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentSteps(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentRestingHeartRate(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentSleep(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentDistance(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentHRV(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentVO2Max(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentHeartRate(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentBloodOxygen(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
    func recentMindfulMinutes(daysBack: Int, completion: @escaping ([HealthQuantitySample]) -> Void) { completion([]) }
}
