import SwiftUI

@main
struct GymTrainerApp: App {
    @StateObject private var api = APIClient()
    @StateObject private var health = HealthKitManager()
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if api.userId == nil {
                    OnboardingView()
                } else {
                    ContentView()
                }
            }
            .environmentObject(api)
            .environmentObject(health)
            .environmentObject(model)
            .task {
                model.configure(api: api, health: health)
                await health.requestAuthorization()
                await model.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthKitWorkoutsChanged)) { _ in
                Task { await model.syncHealth() }
            }
        }
    }
}

/// Estado do app: ficha atual, resumo semanal e sincronização com Saúde/Watch.
@MainActor
final class AppModel: ObservableObject {
    @Published var plan: WorkoutPlan?
    @Published var weekly: WeeklySummary?
    @Published var assessmentStatus: AssessmentStatus?
    @Published var lastError: String?

    private weak var api: APIClient?
    private weak var health: HealthKitManager?

    func configure(api: APIClient, health: HealthKitManager) {
        self.api = api
        self.health = health
        PhoneSessionManager.shared.activate()
        PhoneSessionManager.shared.onWorkoutReceived = { [weak self] summary in
            Task { await self?.upload(summary) }
        }
    }

    func refresh() async {
        guard let api, api.userId != nil else { return }
        do {
            assessmentStatus = try await api.assessmentStatus()
            if let plan = try? await api.currentPlan() {
                self.plan = plan
                PhoneSessionManager.shared.sendPlan(plan)
            }
            await syncHealth()
            weekly = try await api.weeklySummary()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func syncHealth() async {
        guard let api, let health, health.isAuthorized, api.userId != nil else { return }
        do {
            try await api.syncHealth(await health.buildSyncPayload())
            weekly = try await api.weeklySummary()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func upload(_ summary: WorkoutSummary) async {
        var summary = summary
        summary.planId = summary.planId ?? plan?.id
        do {
            try await api?.logWorkout(summary)
            weekly = try await api?.weeklySummary()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
