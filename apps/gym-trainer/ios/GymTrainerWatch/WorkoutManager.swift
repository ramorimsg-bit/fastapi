import Foundation
import HealthKit
import WatchKit

/// Sessão de treino no Apple Watch com HKWorkoutSession + HKLiveWorkoutBuilder.
/// Mede FC e energia ativa em tempo real, grava o treino no app Saúde, guia a ficha
/// (séries, descanso, zona de FC no cardio) e envia o resumo para o iPhone.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // Métricas ao vivo
    @Published var heartRate: Double = 0
    @Published var averageHeartRate: Double = 0
    @Published var maxHeartRate: Double = 0
    @Published var activeEnergy: Double = 0
    @Published var running = false
    @Published var startDate: Date?
    @Published var summary: WorkoutSummary?

    // Progresso da ficha
    @Published var day: PlanDay?
    @Published var exerciseIndex = 0
    @Published var setNumber = 1
    @Published var loggedSets: [LoggedSet] = []
    @Published var restRemaining: Int = 0
    @Published var inCardio = false

    private var heartRateSeries: [HeartRatePoint] = []
    private var restTask: Task<Void, Never>?

    var currentItem: PlanItem? {
        guard let day, exerciseIndex < day.exercises.count else { return nil }
        return day.exercises[exerciseIndex]
    }

    /// Zona-alvo de FC do cardio da ficha.
    var targetZone: ClosedRange<Double>? {
        guard inCardio, let bpm = day?.cardio.targetHrBpm, let lo = bpm.first, let hi = bpm.last else { return nil }
        return Double(lo)...Double(hi)
    }

    func requestAuthorization() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning), HKObjectType.activitySummaryType(),
        ]
        try? await healthStore.requestAuthorization(toShare: share, read: read)
    }

    // MARK: Ciclo da sessão

    func start(day: PlanDay?) async {
        self.day = day
        exerciseIndex = 0
        setNumber = 1
        loggedSets = []
        heartRateSeries = []
        summary = nil
        inCardio = day?.exercises.isEmpty ?? false

        let config = HKWorkoutConfiguration()
        config.activityType = inCardio ? .mixedCardio : .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            running = true
        } catch {
            print("Falha ao iniciar treino: \(error)")
        }
    }

    func togglePause() {
        guard let session else { return }
        session.state == .running ? session.pause() : session.resume()
    }

    func end() {
        restTask?.cancel()
        session?.end()
    }

    // MARK: Ficha

    func logSet(reps: Int, weight: Double) {
        guard let item = currentItem else { return }
        loggedSets.append(LoggedSet(exerciseId: item.exercise.id, setNumber: setNumber, reps: reps, weightKg: weight))
        WKInterfaceDevice.current().play(.success)
        if setNumber < item.sets {
            setNumber += 1
            startRest(seconds: item.restS)
        } else {
            nextExercise()
        }
    }

    func nextExercise() {
        restTask?.cancel()
        restRemaining = 0
        setNumber = 1
        exerciseIndex += 1
        if currentItem == nil { startCardio() }
    }

    func startCardio() {
        guard day?.cardio != nil, !inCardio else { return }
        inCardio = true
        // Marca o início do cardio no treino gravado no app Saúde.
        let event = HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: .now, duration: 0), metadata: nil)
        builder?.addWorkoutEvents([event]) { _, _ in }
        WKInterfaceDevice.current().play(.start)
    }

    private func startRest(seconds: Int) {
        restTask?.cancel()
        restRemaining = seconds
        restTask = Task { [weak self] in
            while let self, self.restRemaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.restRemaining -= 1
                if self.restRemaining == 3 { WKInterfaceDevice.current().play(.click) }
            }
            if !Task.isCancelled { WKInterfaceDevice.current().play(.notification) }
        }
    }

    // MARK: Métricas

    private func update(_ statistics: HKStatistics) {
        switch statistics.quantityType {
        case HKQuantityType(.heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            heartRate = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? 0
            averageHeartRate = statistics.averageQuantity()?.doubleValue(for: unit) ?? 0
            maxHeartRate = max(maxHeartRate, heartRate)
            if heartRate > 0 { heartRateSeries.append(HeartRatePoint(timestamp: .now, bpm: heartRate)) }
            if let zone = targetZone, heartRate > 0, !zone.contains(heartRate) {
                // Aviso háptico: acima da zona (diminua) ou abaixo (aumente o ritmo).
                WKInterfaceDevice.current().play(heartRate > zone.upperBound ? .directionDown : .directionUp)
            }
        case HKQuantityType(.activeEnergyBurned):
            activeEnergy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        default:
            break
        }
    }

    private func finish(endDate: Date) async {
        guard let builder, let startDate else { return }
        do {
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            let result = WorkoutSummary(
                dayLabel: day?.label,
                startedAt: startDate,
                endedAt: endDate,
                sets: loggedSets,
                heartRate: heartRateSeries,
                activeEnergyKcal: activeEnergy,
                avgHr: averageHeartRate,
                maxHr: maxHeartRate,
                source: "apple_watch",
                healthkitUuid: workout?.uuid.uuidString
            )
            summary = result
            WatchSessionManager.shared.send(result)
        } catch {
            print("Falha ao finalizar treino: \(error)")
        }
        running = false
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in await self.finish(endDate: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Erro na sessão: \(error)")
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            Task { @MainActor in self.update(statistics) }
        }
    }
}
