import SwiftUI

struct PlanView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let plan = model.plan {
                    List {
                        Section("Divisão: \(plan.split.joined(separator: " / "))") {
                            ForEach(plan.days.indices, id: \.self) { i in
                                let day = plan.days[i]
                                NavigationLink {
                                    PlanDayView(day: day)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text("Treino \(Character(UnicodeScalar(65 + i)!)) · \(day.label)").font(.headline)
                                        Text("\(day.exercises.count) exercícios · \(day.cardio.durationMin) min de cardio · ~\(day.estimatedMinutes) min · ~\(day.estimatedKcal) kcal")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Section("Periodização (8 semanas)") {
                            ForEach(plan.periodization, id: \.weeks) { p in
                                VStack(alignment: .leading) {
                                    Text("Semana \(p.weeks)").bold()
                                    Text(p.focus).font(.callout)
                                }
                            }
                            Text(plan.progressionRule).font(.footnote).foregroundStyle(.secondary)
                        }
                        Section("Cardio semanal") {
                            Text("\(plan.weeklyCardioMin) min na ficha").bold()
                            Text(plan.weeklyCardioNote).font(.footnote)
                        }
                        Section { Text("Ficha válida até \(plan.validUntil) (reavaliação bimestral).").font(.footnote) }
                    }
                } else {
                    ContentUnavailableView("Sem ficha ainda", systemImage: "list.bullet.clipboard",
                                           description: Text("Faça sua avaliação física para o Coach montar sua ficha."))
                }
            }
            .navigationTitle("Ficha de treino")
        }
    }
}

struct PlanDayView: View {
    let day: PlanDay

    var body: some View {
        List {
            Section("Aquecimento") { Text(day.warmup) }
            Section("Musculação") {
                ForEach(day.exercises) { item in
                    NavigationLink {
                        ExerciseDetailView(exercise: item.exercise, item: item)
                    } label: {
                        HStack {
                            Text("\(item.order)").font(.title3.bold()).foregroundStyle(.orange).frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(item.exercise.name).font(.headline)
                                Text("\(item.sets) x \(item.reps) · descanso \(item.restS)s · RIR \(item.rir) · cadência \(item.tempo)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Cardio") {
                NavigationLink {
                    ExerciseDetailView(exercise: day.cardio.exercise, item: nil, cardio: day.cardio)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.cardio.exercise.name).font(.headline)
                        Text("\(day.cardio.type): \(day.cardio.durationMin) min + \(day.cardio.warmupMin) min de aquecimento")
                        Label("\(day.cardio.targetZone): \(day.cardio.targetHrBpm.first ?? 0)-\(day.cardio.targetHrBpm.last ?? 0) bpm",
                              systemImage: "heart.fill").foregroundStyle(.red).font(.callout)
                        Text("~\(Int(day.cardio.estimatedKcal)) kcal · \(day.cardio.when)").font(.caption).foregroundStyle(.secondary)
                        if let note = day.cardio.note { Text(note).font(.caption2) }
                    }
                }
                if let hiit = day.cardio.hiitOption {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Opção HIIT").font(.headline)
                        Text(hiit.description).font(.callout)
                        Text("Tiros em \(hiit.workZone): \(hiit.workHrBpm.first ?? 0)-\(hiit.workHrBpm.last ?? 0) bpm · ~\(Int(hiit.estimatedKcal)) kcal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Volta à calma") { Text(day.cooldown) }
        }
        .navigationTitle(day.label)
    }
}
