import Foundation

// Modelos compartilhados entre iPhone e Apple Watch (espelham a API do backend).
// O JSONDecoder usa .convertFromSnakeCase, então os nomes ficam em camelCase.

struct Demonstration: Codable, Hashable {
    let steps: [String]
    let cues: [String]
    let commonMistakes: [String]
    let breathing: String
    let tempo: String
    let tempoLegend: String
    let videoUrl: URL
}

struct ExerciseInfo: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let pattern: String
    let muscles: [String]
    let equipment: String
    let level: Int
    let isCardio: Bool
    let demonstration: Demonstration
    let restrictions: [String]
    let alternatives: [String]
}

struct PlanItem: Codable, Hashable, Identifiable {
    var id: Int { order }
    let order: Int
    let exercise: ExerciseInfo
    let sets: Int
    let reps: String
    let restS: Int
    let rir: String
    let tempo: String
}

struct HIITOption: Codable, Hashable {
    let description: String
    let workZone: String
    let workHrBpm: [Int]
    let totalMin: Int
    let estimatedKcal: Double
}

struct CardioBlock: Codable, Hashable {
    let exercise: ExerciseInfo
    let type: String
    let durationMin: Int
    let warmupMin: Int
    let targetZone: String
    let targetHrBpm: [Int]
    let estimatedKcal: Double
    let when: String
    let note: String?
    let hiitOption: HIITOption?
}

struct PlanDay: Codable, Hashable, Identifiable {
    var id: String { label }
    let label: String
    let warmup: String
    let exercises: [PlanItem]
    let cardio: CardioBlock
    let cooldown: String
    let estimatedMinutes: Int
    let estimatedKcal: Int
}

struct Nutrition: Codable, Hashable {
    let kcal: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let waterMl: Int
    let fiberG: Int
}

struct Periodization: Codable, Hashable {
    let weeks: String
    let focus: String
}

struct WorkoutPlan: Codable, Hashable, Identifiable {
    let id: String
    let goal: String
    let split: [String]
    let days: [PlanDay]
    let periodization: [Periodization]
    let progressionRule: String
    let weeklyCardioMin: Int
    let weeklyCardioNote: String
    let nutrition: Nutrition
    let alerts: [String]
    let validUntil: String
}

/// Série registrada no relógio ou no iPhone.
struct LoggedSet: Codable, Hashable {
    let exerciseId: String
    let setNumber: Int
    var reps: Int?
    var weightKg: Double?
    var durationS: Int?
    var rpe: Double?
}

struct HeartRatePoint: Codable, Hashable {
    let timestamp: Date
    let bpm: Double
}

/// Resumo de uma sessão enviado do Apple Watch para o iPhone e depois para a API.
struct WorkoutSummary: Codable, Hashable {
    var planId: String?
    var dayLabel: String?
    let startedAt: Date
    let endedAt: Date
    var sets: [LoggedSet]
    var heartRate: [HeartRatePoint]
    var activeEnergyKcal: Double?
    var avgHr: Double?
    var maxHr: Double?
    var source: String
    var healthkitUuid: String?
}

enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
