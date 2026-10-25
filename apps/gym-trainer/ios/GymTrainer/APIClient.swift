import Foundation

/// Cliente da GymTrainer API.
@MainActor
final class APIClient: ObservableObject {
    @Published var userId: String? = UserDefaults.standard.string(forKey: "userId") {
        didSet { UserDefaults.standard.set(userId, forKey: "userId") }
    }

    var baseURL: URL = URL(string: UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://localhost:8000")!

    struct APIError: LocalizedError {
        let status: Int
        let body: String
        var errorDescription: String? { "Erro \(status): \(body)" }
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: Encodable? = nil) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONCoding.encoder.encode(body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONCoding.decoder.decode(T.self, from: data)
    }

    private var user: String {
        get throws {
            guard let userId else { throw APIError(status: 401, body: "Cadastro não realizado") }
            return userId
        }
    }

    // MARK: Endpoints

    struct UserPayload: Codable {
        var name: String
        var sex: String
        var birthDate: String
        var heightCm: Double
        var goal: String
        var experience: String
        var activityLevel: String
        var daysPerWeek: Int
        var sessionMinutes: Int
        var injuries: [String]
    }

    struct CreatedUser: Codable { let id: String }

    func createUser(_ payload: UserPayload) async throws {
        let created: CreatedUser = try await request("POST", "users", body: payload)
        userId = created.id
    }

    func currentPlan() async throws -> WorkoutPlan {
        let id = try user
        return try await request("GET", "users/\(id)/plans/current")
    }

    func submitAssessment(_ payload: AssessmentPayload) async throws -> AssessmentResponse {
        let id = try user
        return try await request("POST", "users/\(id)/assessments", body: payload)
    }

    func assessmentStatus() async throws -> AssessmentStatus {
        let id = try user
        return try await request("GET", "users/\(id)/assessments/status")
    }

    func logWorkout(_ summary: WorkoutSummary) async throws {
        let id = try user
        let _: EmptyResponse = try await request("POST", "users/\(id)/workouts", body: summary)
    }

    func syncHealth(_ payload: HealthSyncPayload) async throws {
        let id = try user
        let _: EmptyResponse = try await request("POST", "users/\(id)/health/sync", body: payload)
    }

    func weeklySummary() async throws -> WeeklySummary {
        let id = try user
        return try await request("GET", "users/\(id)/summary/weekly")
    }

    func chat(_ messages: [ChatMessage]) async throws -> ChatMessage {
        struct Body: Encodable { let messages: [ChatMessage] }
        let id = try user
        return try await request("POST", "users/\(id)/coach/chat", body: Body(messages: messages))
    }
}

struct EmptyResponse: Decodable {
    init(from decoder: Decoder) throws {}
}

struct ChatMessage: Codable, Hashable, Identifiable {
    var id = UUID()
    let role: String
    let content: String
    enum CodingKeys: String, CodingKey { case role, content }
}

struct AssessmentStatus: Codable {
    let due: Bool
    let nextAssessment: String
    let daysLeft: Int
}

struct WeeklySummary: Codable {
    let workouts: Int
    let planned: Int
    let kcal: Double
    let minutes: Int
    let volumeLoadKg: Double
}

struct AssessmentPayload: Codable {
    var weightKg: Double
    var skinfolds: [String: Double]
    var circumferences: [String: Double]
    var exams: Exams
    var parq: [String: Bool]
    var pushupsMax: Int?
    var plankSeconds: Int?
    var healthkitBodyFatPct: Double?

    struct Exams: Codable {
        var systolicBp: Int?
        var diastolicBp: Int?
        var restingHr: Int?
        var fastingGlucose: Double?
        var hba1c: Double?
        var totalCholesterol: Double?
        var ldl: Double?
        var hdl: Double?
        var triglycerides: Double?
        var vitaminD: Double?
        var vo2max: Double?
        var conditions: [String] = []
    }
}

struct AssessmentResponse: Codable {
    struct Results: Codable {
        struct Composition: Codable {
            let bmi: Double
            let bmiCategory: String
            let bodyFatPct: Double?
            let bodyFatMethod: String?
            let bodyFatCategory: String?
            let fatMassKg: Double?
            let leanMassKg: Double?
        }
        struct Progress: Codable {
            let daysBetween: Int
            let weightKg: Double
            let summary: String
        }
        let composition: Composition
        let alerts: [String]
        let needsMedicalClearance: Bool
        let nextAssessment: String
        let nutrition: Nutrition
        let progress: Progress?
    }
    let id: String
    let results: Results
}

struct HealthSyncPayload: Codable {
    var weightKg: Double?
    var bodyFatPct: Double?
    var leanMassKg: Double?
    var restingHr: Double?
    var hrvMs: Double?
    var vo2max: Double?
    var stepsToday: Int?
    var activeEnergyTodayKcal: Double?
    var workouts: [WorkoutSummary]
}
