import Foundation
import HealthKit

/// Integração com o app Saúde do iPhone (HealthKit).
/// Lê frequência cardíaca, energia ativa, passos, composição corporal, VO2máx e treinos
/// gravados pelo Apple Watch; grava peso/% de gordura das avaliações e os treinos do app.
@MainActor
final class HealthKitManager: ObservableObject {
    let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var latestHeartRate: Double?
    @Published var restingHeartRate: Double?
    @Published var activeEnergyToday: Double?
    @Published var stepsToday: Int?
    @Published var vo2max: Double?

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.stepCount),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.vo2Max),
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.leanBodyMass),
        HKQuantityType(.height),
        HKQuantityType(.waistCircumference),
        HKCharacteristicType(.dateOfBirth),
        HKCharacteristicType(.biologicalSex),
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
    ]

    private let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.leanBodyMass),
        HKQuantityType(.waistCircumference),
    ]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
            await refreshToday()
            enableBackgroundDelivery()
        } catch {
            print("HealthKit: falha na autorização: \(error)")
        }
    }

    // MARK: Leitura

    func mostRecent(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try? await descriptor.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    func sumToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum
        )
        return try? await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
    }

    func refreshToday() async {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        latestHeartRate = await mostRecent(.heartRate, unit: bpm)
        restingHeartRate = await mostRecent(.restingHeartRate, unit: bpm)
        vo2max = await mostRecent(.vo2Max, unit: HKUnit(from: "ml/kg*min"))
        activeEnergyToday = await sumToday(.activeEnergyBurned, unit: .kilocalorie())
        stepsToday = (await sumToday(.stepCount, unit: .count())).map { Int($0) }
    }

    /// Amostras de FC de um treino (usadas no gráfico e no cálculo de calorias da API).
    func heartRateSamples(for workout: HKWorkout) async -> [HeartRatePoint] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return samples.map { HeartRatePoint(timestamp: $0.startDate, bpm: $0.quantity.doubleValue(for: bpm)) }
    }

    /// Treinos de musculação/cardio gravados no app Saúde (inclusive pelo app Treino do Apple Watch).
    func recentWorkouts(days: Int = 7) async -> [WorkoutSummary] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let gymTypes: [HKWorkoutActivityType] = [
            .traditionalStrengthTraining, .functionalStrengthTraining, .highIntensityIntervalTraining,
            .running, .walking, .cycling, .elliptical, .rowing, .stairClimbing, .coreTraining,
        ]
        let typePredicates = gymTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: .now),
            NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates),
        ])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let workouts = (try? await descriptor.result(for: store)) ?? []
        var summaries: [WorkoutSummary] = []
        for w in workouts {
            let hr = await heartRateSamples(for: w)
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let bpm = HKUnit.count().unitDivided(by: .minute())
            let hrStats = w.statistics(for: HKQuantityType(.heartRate))
            summaries.append(WorkoutSummary(
                startedAt: w.startDate,
                endedAt: w.endDate,
                sets: [],
                heartRate: hr,
                activeEnergyKcal: energy,
                avgHr: hrStats?.averageQuantity()?.doubleValue(for: bpm),
                maxHr: hrStats?.maximumQuantity()?.doubleValue(for: bpm),
                source: w.sourceRevision.productType?.contains("Watch") == true ? "apple_watch" : "iphone",
                healthkitUuid: w.uuid.uuidString
            ))
        }
        return summaries
    }

    /// Monta o lote enviado para a API (/health/sync).
    func buildSyncPayload() async -> HealthSyncPayload {
        await refreshToday()
        return HealthSyncPayload(
            weightKg: await mostRecent(.bodyMass, unit: .gramUnit(with: .kilo)),
            bodyFatPct: (await mostRecent(.bodyFatPercentage, unit: .percent())).map { $0 * 100 },
            leanMassKg: await mostRecent(.leanBodyMass, unit: .gramUnit(with: .kilo)),
            restingHr: restingHeartRate,
            hrvMs: await mostRecent(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)),
            vo2max: vo2max,
            stepsToday: stepsToday,
            activeEnergyTodayKcal: activeEnergyToday,
            workouts: await recentWorkouts()
        )
    }

    // MARK: Escrita

    /// Grava os resultados da avaliação bimestral no app Saúde.
    func saveAssessment(weightKg: Double, bodyFatPct: Double?, leanMassKg: Double?, waistCm: Double?) async {
        let now = Date.now
        var samples: [HKQuantitySample] = [
            HKQuantitySample(type: HKQuantityType(.bodyMass),
                             quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg),
                             start: now, end: now),
        ]
        if let bodyFatPct {
            samples.append(HKQuantitySample(type: HKQuantityType(.bodyFatPercentage),
                                            quantity: HKQuantity(unit: .percent(), doubleValue: bodyFatPct / 100),
                                            start: now, end: now))
        }
        if let leanMassKg {
            samples.append(HKQuantitySample(type: HKQuantityType(.leanBodyMass),
                                            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: leanMassKg),
                                            start: now, end: now))
        }
        if let waistCm {
            samples.append(HKQuantitySample(type: HKQuantityType(.waistCircumference),
                                            quantity: HKQuantity(unit: .meterUnit(with: .centi), doubleValue: waistCm),
                                            start: now, end: now))
        }
        try? await store.save(samples)
    }

    // MARK: Atualizações em segundo plano

    /// Avisa o app quando o Apple Watch grava um novo treino, para sincronizar com a API.
    private func enableBackgroundDelivery() {
        let workoutType = HKObjectType.workoutType()
        store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { _, completion, _ in
            NotificationCenter.default.post(name: .healthKitWorkoutsChanged, object: nil)
            completion()
        }
        store.execute(query)
    }
}

extension Notification.Name {
    static let healthKitWorkoutsChanged = Notification.Name("healthKitWorkoutsChanged")
}
