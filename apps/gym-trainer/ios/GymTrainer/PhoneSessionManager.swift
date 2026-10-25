import Foundation
import WatchConnectivity

/// Ponte iPhone ⇄ Apple Watch: envia a ficha atual para o relógio e recebe os treinos concluídos.
final class PhoneSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    /// Chamado quando o relógio termina um treino.
    var onWorkoutReceived: ((WorkoutSummary) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendPlan(_ plan: WorkoutPlan) {
        guard WCSession.default.activationState == .activated,
              let data = try? JSONCoding.encoder.encode(plan) else { return }
        // applicationContext sempre mantém só a versão mais recente da ficha no relógio.
        try? WCSession.default.updateApplicationContext(["plan": data])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["workout"] as? Data,
              let summary = try? JSONCoding.decoder.decode(WorkoutSummary.self, from: data) else { return }
        DispatchQueue.main.async { self.onWorkoutReceived?(summary) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
