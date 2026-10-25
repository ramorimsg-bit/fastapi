import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Hoje", systemImage: "flame.fill") }
            PlanView()
                .tabItem { Label("Ficha", systemImage: "list.bullet.clipboard") }
            AssessmentFormView()
                .tabItem { Label("Avaliação", systemImage: "figure.arms.open") }
            CoachChatView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
        }
        .tint(.orange)
    }
}

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var health: HealthKitManager

    var body: some View {
        NavigationStack {
            List {
                if let status = model.assessmentStatus {
                    Section {
                        if status.due {
                            Label("Hora da sua avaliação física bimestral!", systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        } else {
                            Label("Próxima avaliação em \(status.daysLeft) dias", systemImage: "calendar")
                        }
                    }
                }

                Section("Hoje (app Saúde / Apple Watch)") {
                    MetricRow(icon: "heart.fill", color: .red, title: "Frequência cardíaca",
                              value: health.latestHeartRate.map { "\(Int($0)) bpm" })
                    MetricRow(icon: "heart.text.square", color: .pink, title: "FC de repouso",
                              value: health.restingHeartRate.map { "\(Int($0)) bpm" })
                    MetricRow(icon: "flame.fill", color: .orange, title: "Energia ativa",
                              value: health.activeEnergyToday.map { "\(Int($0)) kcal" })
                    MetricRow(icon: "figure.walk", color: .green, title: "Passos",
                              value: health.stepsToday.map { "\($0)" })
                    MetricRow(icon: "lungs.fill", color: .teal, title: "VO2máx",
                              value: health.vo2max.map { String(format: "%.1f ml/kg/min", $0) })
                }

                if let w = model.weekly {
                    Section("Últimos 7 dias") {
                        MetricRow(icon: "dumbbell.fill", color: .blue, title: "Treinos",
                                  value: "\(w.workouts) de \(w.planned)")
                        MetricRow(icon: "flame", color: .orange, title: "Calorias em treino",
                                  value: "\(Int(w.kcal)) kcal")
                        MetricRow(icon: "timer", color: .purple, title: "Tempo", value: "\(w.minutes) min")
                        MetricRow(icon: "scalemass", color: .gray, title: "Volume (carga x reps)",
                                  value: "\(Int(w.volumeLoadKg)) kg")
                    }
                }

                if let n = model.plan?.nutrition {
                    Section("Metas nutricionais diárias") {
                        MetricRow(icon: "fork.knife", color: .green, title: "Calorias", value: "\(n.kcal) kcal")
                        MetricRow(icon: "p.circle", color: .red, title: "Proteína", value: "\(n.proteinG) g")
                        MetricRow(icon: "c.circle", color: .yellow, title: "Carboidratos", value: "\(n.carbsG) g")
                        MetricRow(icon: "f.circle", color: .blue, title: "Gorduras", value: "\(n.fatG) g")
                        MetricRow(icon: "drop.fill", color: .cyan, title: "Água", value: "\(n.waterMl) ml")
                    }
                }

                if let alerts = model.plan?.alerts, !alerts.isEmpty {
                    Section("Atenção") {
                        ForEach(alerts, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
                    }
                }
            }
            .navigationTitle("GymTrainer")
            .refreshable { await model.refresh() }
        }
    }
}

struct MetricRow: View {
    let icon: String
    let color: Color
    let title: String
    let value: String?

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 28)
            Text(title)
            Spacer()
            Text(value ?? "—").bold().monospacedDigit()
        }
    }
}
