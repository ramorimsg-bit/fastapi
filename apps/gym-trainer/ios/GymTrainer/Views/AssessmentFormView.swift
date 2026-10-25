import SwiftUI

/// Avaliação física bimestral: antropometria, dobras cutâneas, exames e PAR-Q.
struct AssessmentFormView: View {
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var health: HealthKitManager
    @EnvironmentObject var model: AppModel

    @State private var weight = ""
    @State private var skinfolds: [String: String] = [:]
    @State private var circumferences: [String: String] = [:]
    @State private var exams = AssessmentPayload.Exams()
    @State private var parq: [String: Bool] = [:]
    @State private var result: AssessmentResponse?
    @State private var error: String?
    @State private var sending = false

    private let skinfoldFields = [
        ("chest", "Peitoral"), ("midaxillary", "Axilar média"), ("triceps", "Tríceps"),
        ("subscapular", "Subescapular"), ("abdominal", "Abdominal"), ("suprailiac", "Supra-ilíaca"), ("thigh", "Coxa"),
    ]
    private let circumferenceFields = [
        ("neck", "Pescoço"), ("chest", "Tórax"), ("waist", "Cintura"), ("abdomen", "Abdômen"), ("hip", "Quadril"),
        ("right_arm", "Braço direito"), ("left_arm", "Braço esquerdo"), ("right_thigh", "Coxa direita"),
        ("left_thigh", "Coxa esquerda"), ("right_calf", "Panturrilha direita"), ("left_calf", "Panturrilha esquerda"),
    ]
    private let parqQuestions = [
        ("heart_condition", "Algum médico já disse que você tem problema cardíaco?"),
        ("chest_pain_activity", "Sente dor no peito ao praticar atividade física?"),
        ("chest_pain_rest", "Sentiu dor no peito no último mês, em repouso?"),
        ("dizziness_or_fainting", "Perde o equilíbrio por tontura ou já desmaiou?"),
        ("bone_joint_problem", "Tem problema ósseo/articular que piora com exercício?"),
        ("bp_or_heart_medication", "Toma remédio para pressão ou coração?"),
        ("other_reason", "Sabe de outra razão para não fazer atividade física?"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Peso") {
                    NumberField(title: "Peso (kg)", text: $weight)
                }
                Section {
                    ForEach(skinfoldFields, id: \.0) { key, label in
                        NumberField(title: "\(label) (mm)", text: entry($skinfolds, key))
                    }
                } header: {
                    Text("Dobras cutâneas")
                } footer: {
                    Text("Lado direito, média de 2-3 medidas com adipômetro. 7 dobras = Jackson & Pollock 7; homens: peitoral/abdominal/coxa; mulheres: tríceps/supra-ilíaca/coxa = protocolo de 3 dobras. Sem adipômetro, informe pescoço, cintura e quadril.")
                }
                Section("Circunferências (cm)") {
                    ForEach(circumferenceFields, id: \.0) { key, label in
                        NumberField(title: label, text: entry($circumferences, key))
                    }
                }
                Section("Exames") {
                    IntField(title: "PA sistólica (mmHg)", value: $exams.systolicBp)
                    IntField(title: "PA diastólica (mmHg)", value: $exams.diastolicBp)
                    IntField(title: "FC de repouso (bpm)", value: $exams.restingHr)
                    DoubleField(title: "Glicemia de jejum (mg/dL)", value: $exams.fastingGlucose)
                    DoubleField(title: "HbA1c (%)", value: $exams.hba1c)
                    DoubleField(title: "LDL (mg/dL)", value: $exams.ldl)
                    DoubleField(title: "HDL (mg/dL)", value: $exams.hdl)
                    DoubleField(title: "Triglicerídeos (mg/dL)", value: $exams.triglycerides)
                    DoubleField(title: "Vitamina D (ng/mL)", value: $exams.vitaminD)
                    Button("Preencher FC de repouso e VO2máx do Apple Watch") {
                        exams.restingHr = health.restingHeartRate.map { Int($0) }
                        exams.vo2max = health.vo2max
                    }
                }
                Section("PAR-Q (triagem de saúde)") {
                    ForEach(parqQuestions, id: \.0) { key, question in
                        Toggle(question, isOn: Binding(get: { parq[key] ?? false }, set: { parq[key] = $0 }))
                            .font(.callout)
                    }
                }
                Section {
                    Button(sending ? "Enviando..." : "Avaliar e gerar nova ficha") { Task { await submit() } }
                        .disabled(Double(weight.replacingOccurrences(of: ",", with: ".")) == nil || sending)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let r = result?.results { ResultSection(results: r) }
            }
            .navigationTitle("Avaliação física")
        }
    }

    private func entry(_ dict: Binding<[String: String]>, _ key: String) -> Binding<String> {
        Binding(get: { dict.wrappedValue[key] ?? "" }, set: { dict.wrappedValue[key] = $0 })
    }

    private func numbers(_ dict: [String: String]) -> [String: Double] {
        dict.compactMapValues { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    private func submit() async {
        guard let w = Double(weight.replacingOccurrences(of: ",", with: ".")) else { return }
        sending = true
        defer { sending = false }
        let payload = AssessmentPayload(
            weightKg: w,
            skinfolds: numbers(skinfolds),
            circumferences: numbers(circumferences),
            exams: exams,
            parq: parq,
            healthkitBodyFatPct: (await health.buildSyncPayload()).bodyFatPct
        )
        do {
            let response = try await api.submitAssessment(payload)
            result = response
            let c = response.results.composition
            await health.saveAssessment(weightKg: w, bodyFatPct: c.bodyFatPct, leanMassKg: c.leanMassKg,
                                        waistCm: numbers(circumferences)["waist"])
            await model.refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ResultSection: View {
    let results: AssessmentResponse.Results

    var body: some View {
        Section("Resultado") {
            let c = results.composition
            LabeledContent("IMC", value: String(format: "%.1f (%@)", c.bmi, c.bmiCategory))
            if let bf = c.bodyFatPct {
                LabeledContent("Gordura corporal", value: String(format: "%.1f%% (%@)", bf, c.bodyFatCategory ?? ""))
                Text(c.bodyFatMethod ?? "").font(.caption).foregroundStyle(.secondary)
            }
            if let lean = c.leanMassKg { LabeledContent("Massa magra", value: String(format: "%.1f kg", lean)) }
            if let fat = c.fatMassKg { LabeledContent("Massa gorda", value: String(format: "%.1f kg", fat)) }
            if let p = results.progress {
                LabeledContent("Evolução (\(p.daysBetween) dias)", value: p.summary)
            }
            LabeledContent("Próxima avaliação", value: results.nextAssessment)
            if results.needsMedicalClearance {
                Label("Apresente liberação médica antes de treinos intensos.", systemImage: "stethoscope")
                    .foregroundStyle(.red)
            }
            ForEach(results.alerts, id: \.self) { Text("• \($0)").font(.callout) }
        }
    }
}

struct NumberField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
        }
    }
}

struct IntField: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        NumberField(title: title, text: Binding(
            get: { value.map(String.init) ?? "" },
            set: { value = Int($0) }
        ))
    }
}

struct DoubleField: View {
    let title: String
    @Binding var value: Double?

    var body: some View {
        NumberField(title: title, text: Binding(
            get: { value.map { String(format: "%g", $0) } ?? "" },
            set: { value = Double($0.replacingOccurrences(of: ",", with: ".")) }
        ))
    }
}
