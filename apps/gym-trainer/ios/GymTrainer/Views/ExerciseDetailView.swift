import SwiftUI

/// Demonstração de execução de um exercício: passo a passo animado, cadência,
/// respiração, pontos-chave, erros comuns e vídeo.
struct ExerciseDetailView: View {
    let exercise: ExerciseInfo
    let item: PlanItem?
    var cardio: CardioBlock? = nil

    @State private var currentStep = 0
    @State private var isPlaying = false
    @Environment(\.openURL) private var openURL

    private var demo: Demonstration { exercise.demonstration }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let item { prescription(item) }
                if let cardio { cardioPrescription(cardio) }
                stepPlayer
                if !exercise.isCardio { TempoView(tempo: demo.tempo, legend: demo.tempoLegend) }
                infoCard("Respiração", icon: "wind", color: .teal, lines: [demo.breathing])
                infoCard("Pontos-chave", icon: "checkmark.seal.fill", color: .green, lines: demo.cues)
                infoCard("Erros comuns", icon: "xmark.octagon.fill", color: .red, lines: demo.commonMistakes)
                Button {
                    openURL(demo.videoUrl)
                } label: {
                    Label("Ver vídeo de demonstração", systemImage: "play.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if !exercise.alternatives.isEmpty {
                    Text("Substitutos: \(exercise.alternatives.joined(separator: ", "))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name).font(.largeTitle.bold())
            Text(exercise.muscles.joined(separator: " · ")).foregroundStyle(.orange)
            Label(exercise.equipment, systemImage: "dumbbell").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func prescription(_ item: PlanItem) -> some View {
        HStack {
            stat("\(item.sets)", "séries")
            stat(item.reps, "reps")
            stat("\(item.restS)s", "descanso")
            stat(item.rir, "RIR")
        }
    }

    private func cardioPrescription(_ c: CardioBlock) -> some View {
        HStack {
            stat("\(c.durationMin)", "min")
            stat("\(c.targetHrBpm.first ?? 0)-\(c.targetHrBpm.last ?? 0)", "bpm alvo")
            stat("~\(Int(c.estimatedKcal))", "kcal")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Passo a passo da execução, com reprodução automática.
    private var stepPlayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Execução passo a passo").font(.headline)
                Spacer()
                Button(isPlaying ? "Pausar" : "Reproduzir", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    isPlaying.toggle()
                }
                .buttonStyle(.bordered)
            }
            ForEach(demo.steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                        .background(i == currentStep ? Color.orange : Color.gray.opacity(0.2), in: Circle())
                        .foregroundStyle(i == currentStep ? .white : .primary)
                    Text(demo.steps[i])
                        .fontWeight(i == currentStep ? .semibold : .regular)
                }
                .onTapGesture { currentStep = i }
                .animation(.easeInOut, value: currentStep)
            }
        }
        .task(id: isPlaying) {
            while isPlaying {
                try? await Task.sleep(for: .seconds(3))
                currentStep = (currentStep + 1) % demo.steps.count
            }
        }
    }

    private func infoCard(_ title: String, icon: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
            ForEach(lines, id: \.self) { Text("• \($0)") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Metrônomo visual da cadência (ex.: 3-1-1-0 = 3 s descendo, 1 s pausa, 1 s subindo, 0 s em cima).
struct TempoView: View {
    let tempo: String
    let legend: String
    @State private var phase = 0
    @State private var running = false

    private var parts: [Int] { tempo.split(separator: "-").compactMap { Int($0) } }
    private let labels = ["Descida", "Pausa", "Subida", "Topo"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cadência \(tempo)").font(.headline)
                Spacer()
                Button(running ? "Parar" : "Metrônomo", systemImage: "metronome") { running.toggle() }
                    .buttonStyle(.bordered)
            }
            if parts.count == 4 {
                HStack {
                    ForEach(0..<4, id: \.self) { i in
                        VStack {
                            Text("\(parts[i])s").bold()
                            Text(labels[i]).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .background(running && phase == i ? Color.orange : Color.gray.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Text(legend).font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: running) {
            guard parts.count == 4 else { return }
            while running {
                if parts[phase] > 0 { try? await Task.sleep(for: .seconds(parts[phase])) }
                phase = (phase + 1) % 4
            }
        }
    }
}
