import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var model: AppModel

    @State private var name = ""
    @State private var sex = "male"
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
    @State private var height = 170.0
    @State private var goal = "hypertrophy"
    @State private var experience = "beginner"
    @State private var activity = "moderate"
    @State private var days = 3
    @State private var minutes = 60
    @State private var injuries: Set<String> = []
    @State private var apiURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://localhost:8000"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Sobre você") {
                    TextField("Nome", text: $name)
                    Picker("Sexo biológico", selection: $sex) {
                        Text("Masculino").tag("male")
                        Text("Feminino").tag("female")
                    }
                    DatePicker("Nascimento", selection: $birthDate, displayedComponents: .date)
                    Stepper("Altura: \(Int(height)) cm", value: $height, in: 120...230)
                }
                Section("Objetivo e rotina") {
                    Picker("Objetivo", selection: $goal) {
                        Text("Hipertrofia").tag("hypertrophy")
                        Text("Emagrecimento").tag("fat_loss")
                        Text("Força").tag("strength")
                        Text("Saúde e bem-estar").tag("health")
                        Text("Resistência").tag("endurance")
                    }
                    Picker("Experiência", selection: $experience) {
                        Text("Iniciante (< 6 meses)").tag("beginner")
                        Text("Intermediário (6 meses - 2 anos)").tag("intermediate")
                        Text("Avançado (> 2 anos)").tag("advanced")
                    }
                    Picker("Nível de atividade fora da academia", selection: $activity) {
                        Text("Sedentário").tag("sedentary")
                        Text("Leve").tag("light")
                        Text("Moderado").tag("moderate")
                        Text("Muito ativo").tag("very_active")
                    }
                    Stepper("Dias por semana: \(days)", value: $days, in: 2...6)
                    Stepper("Minutos por treino: \(minutes)", value: $minutes, in: 30...120, step: 15)
                }
                Section("Lesões ou dores") {
                    ForEach([("knee", "Joelho"), ("lower_back", "Lombar"), ("shoulder", "Ombro")], id: \.0) { key, label in
                        Toggle(label, isOn: Binding(
                            get: { injuries.contains(key) },
                            set: { if $0 { injuries.insert(key) } else { injuries.remove(key) } }
                        ))
                    }
                }
                Section("Servidor") {
                    TextField("URL da API", text: $apiURL).textInputAutocapitalization(.never).keyboardType(.URL)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Começar") { Task { await create() } }.disabled(name.isEmpty)
            }
            .navigationTitle("Bem-vindo ao GymTrainer")
        }
    }

    private func create() async {
        UserDefaults.standard.set(apiURL, forKey: "apiBaseURL")
        if let url = URL(string: apiURL) { api.baseURL = url }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        do {
            try await api.createUser(.init(
                name: name, sex: sex, birthDate: formatter.string(from: birthDate), heightCm: height,
                goal: goal, experience: experience, activityLevel: activity, daysPerWeek: days,
                sessionMinutes: minutes, injuries: Array(injuries)
            ))
            await model.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
