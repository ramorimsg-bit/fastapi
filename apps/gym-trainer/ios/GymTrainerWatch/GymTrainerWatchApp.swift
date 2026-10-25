import SwiftUI

@main
struct GymTrainerWatchApp: App {
    @StateObject private var workout = WorkoutManager()
    @StateObject private var connectivity = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if workout.running {
                    SessionView()
                } else if let summary = workout.summary {
                    SummaryView(summary: summary)
                } else {
                    StartView()
                }
            }
            .environmentObject(workout)
            .environmentObject(connectivity)
            .task {
                connectivity.activate()
                await workout.requestAuthorization()
            }
        }
    }
}
