import SwiftUI

/// Conversa com o personal trainer/nutricionista virtual.
struct CoachChatView: View {
    @EnvironmentObject var api: APIClient
    @State private var messages: [ChatMessage] = [
        ChatMessage(role: "assistant", content: "Olá! Sou seu Coach. Posso ajustar sua ficha, explicar a execução de um exercício, revisar sua alimentação ou analisar sua evolução. Como posso ajudar?"),
    ]
    @State private var input = ""
    @State private var loading = false

    private let suggestions = [
        "Como está minha evolução desde a última avaliação?",
        "Senti dor no ombro no supino, o que troco?",
        "Monte um cardápio para bater minhas metas de hoje",
        "Quanto cardio devo fazer esta semana?",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { msg in
                                Text(LocalizedStringKey(msg.content))
                                    .padding(12)
                                    .background(msg.role == "user" ? Color.orange.opacity(0.2) : Color.gray.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 14))
                                    .frame(maxWidth: .infinity, alignment: msg.role == "user" ? .trailing : .leading)
                                    .id(msg.id)
                            }
                            if loading { ProgressView().padding() }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { proxy.scrollTo(messages.last?.id) }
                }
                if messages.count == 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) { send(s) }.buttonStyle(.bordered).font(.caption)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                HStack {
                    TextField("Pergunte ao Coach...", text: $input, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button { send(input) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                }
                .padding()
            }
            .navigationTitle("Coach")
        }
    }

    private func send(_ text: String) {
        messages.append(ChatMessage(role: "user", content: text))
        input = ""
        loading = true
        Task {
            defer { loading = false }
            // A primeira mensagem (saudação local) não vai para a API.
            let history = Array(messages.dropFirst())
            do {
                messages.append(try await api.chat(history))
            } catch {
                messages.append(ChatMessage(role: "assistant", content: "Não consegui falar com o servidor: \(error.localizedDescription)"))
            }
        }
    }
}
