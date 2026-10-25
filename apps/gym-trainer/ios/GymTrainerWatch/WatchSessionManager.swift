import Foundation
import WatchConnectivity

/// Recebe a ficha do iPhone e envia os treinos concluídos de volta.
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    @Published var plan: WorkoutPlan?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ summary: WorkoutSummary) {
        guard let data = try? JSONCoding.encoder.encode(summary) else { return }
        // transferUserInfo é entregue mesmo se o iPhone estiver fora de alcance (fila).
        WCSession.default.transferUserInfo(["workout": data])
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["plan"] as? Data,
              let plan = try? JSONCoding.decoder.decode(WorkoutPlan.self, from: data) else { return }
        DispatchQueue.main.async { self.plan = plan }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}
