import SwiftUI

struct StartView: View {
    @EnvironmentObject var workout: WorkoutManager
    @EnvironmentObject var connectivity: WatchSessionManager

    var body: some View {
        List {
            if let plan = connectivity.plan {
                Section("Sua ficha") {
                    ForEach(plan.days) { day in
                        Button {
                            Task { await workout.start(day: day) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(day.label).font(.headline)
                                Text("\(day.exercises.count) exercícios · \(day.cardio.durationMin)′ cardio")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Abra o app no iPhone para receber sua ficha.").font(.footnote)
            }
            Section {
                Button("Treino livre", systemImage: "dumbbell") { Task { await workout.start(day: nil) } }
            }
        }
        .navigationTitle("GymTrainer")
    }
}

struct SessionView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        TabView {
            MetricsView()
            if workout.day != nil { ExerciseLogView() }
            ControlsView()
        }
        .tabViewStyle(.verticalPage)
    }
}

struct MetricsView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(elapsed(context.date)).font(.system(.title, design: .rounded).monospacedDigit()).foregroundStyle(.yellow)
                Label("\(Int(workout.heartRate)) bpm", systemImage: "heart.fill")
                    .font(.title3.monospacedDigit()).foregroundStyle(zoneColor)
                Label("\(Int(workout.activeEnergy)) kcal", systemImage: "flame.fill")
                    .font(.title3.monospacedDigit()).foregroundStyle(.orange)
                if let zone = workout.targetZone {
                    Text("Alvo: \(Int(zone.lowerBound))-\(Int(zone.upperBound)) bpm").font(.caption)
                }
                if workout.restRemaining > 0 {
                    Text("Descanso: \(workout.restRemaining)s").font(.headline).foregroundStyle(.cyan)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var zoneColor: Color {
        guard let zone = workout.targetZone else { return .red }
        if workout.heartRate < zone.lowerBound { return .blue }
        if workout.heartRate > zone.upperBound { return .red }
        return .green
    }

    private func elapsed(_ now: Date) -> String {
        let s = Int(now.timeIntervalSince(workout.startDate ?? now))
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}

struct ExerciseLogView: View {
    @EnvironmentObject var workout: WorkoutManager
    @State private var reps = 10
    @State private var weight = 20.0

    var body: some View {
        ScrollView {
            if let item = workout.currentItem {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.exercise.name).font(.headline)
                    Text("Série \(workout.setNumber)/\(item.sets) · \(item.reps) reps").font(.caption)
                    Text("Cadência \(item.tempo) · RIR \(item.rir)").font(.caption2).foregroundStyle(.secondary)
                    Stepper("\(reps) reps", value: $reps, in: 1...50)
                    Stepper(String(format: "%.1f kg", weight), value: $weight, in: 0...400, step: 2.5)
                    Button("Concluir série") { workout.logSet(reps: reps, weight: weight) }
                        .buttonStyle(.borderedProminent).tint(.orange)
                    NavigationLink("Como executar") { WatchDemoView(exercise: item.exercise) }
                    Button("Pular exercício") { workout.nextExercise() }.font(.caption)
                }
            } else if let cardio = workout.day?.cardio {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cardio").font(.headline)
                    Text(cardio.exercise.name)
                    Text("\(cardio.durationMin) min em \(cardio.targetZone)").font(.caption)
                    Text("O relógio vibra se a FC sair da zona-alvo.").font(.caption2).foregroundStyle(.secondary)
                    NavigationLink("Como executar") { WatchDemoView(exercise: cardio.exercise) }
                }
            }
        }
    }
}

struct WatchDemoView: View {
    let exercise: ExerciseInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(exercise.demonstration.steps.indices, id: \.self) { i in
                    Text("\(i + 1). \(exercise.demonstration.steps[i])").font(.caption)
                }
                Divider()
                ForEach(exercise.demonstration.cues, id: \.self) { Text("✓ \($0)").font(.caption2).foregroundStyle(.green) }
                ForEach(exercise.demonstration.commonMistakes, id: \.self) { Text("✗ \($0)").font(.caption2).foregroundStyle(.red) }
            }
        }
        .navigationTitle(exercise.name)
    }
}

struct ControlsView: View {
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            if workout.day != nil && !workout.inCardio {
                Button("Ir para o cardio", systemImage: "figure.run") { workout.startCardio() }
            }
            Button("Pausar/Retomar", systemImage: "playpause.fill") { workout.togglePause() }
            Button("Finalizar", systemImage: "xmark") { workout.end() }.tint(.red)
        }
    }
}

struct SummaryView: View {
    @EnvironmentObject var workout: WorkoutManager
    let summary: WorkoutSummary

    var body: some View {
        List {
            LabeledContent("Duração", value: "\(Int(summary.endedAt.timeIntervalSince(summary.startedAt) / 60)) min")
            LabeledContent("Calorias", value: "\(Int(summary.activeEnergyKcal ?? 0)) kcal")
            LabeledContent("FC média", value: "\(Int(summary.avgHr ?? 0)) bpm")
            LabeledContent("FC máx", value: "\(Int(summary.maxHr ?? 0)) bpm")
            LabeledContent("Séries", value: "\(summary.sets.count)")
            Text("Treino salvo no app Saúde e enviado ao iPhone.").font(.caption2)
            Button("Concluir") { workout.summary = nil }
        }
        .navigationTitle("Resumo")
    }
}
