import SwiftUI
import SwiftData
import DayliCore

/// Assistente Dayli. Fluxo obrigatório:
/// interpretar → contexto permitido → proposta estruturada → validação →
/// prévia → confirmação → execução → resultado.
@MainActor
@Observable
final class AssistantViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case local, remote
        var id: String { rawValue }
        var title: String { self == .local ? "Local" : "Dayli AI" }
    }

    struct PendingProposal {
        let record: AIProposalRecord
        let result: AIValidationResult
        var selected: Set<UUID>
    }

    var mode: Mode = .local
    var input = ""
    var isWorking = false
    var errorMessage: String?
    var pending: PendingProposal?

    private let env: AppEnvironment
    private(set) var conversation: AIConversation

    init(env: AppEnvironment) {
        self.env = env
        let context = env.repository.context
        if let existing = try? context.fetch(FetchDescriptor<AIConversation>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).first {
            conversation = existing
        } else {
            let new = AIConversation()
            context.insert(new)
            context.saveLogged()
            conversation = new
        }
        // Com servidor configurado e consentimento dado, a Dayli AI é o modo padrão.
        if remoteAvailable { mode = .remote }
    }

    var messages: [AIMessage] { conversation.sortedMessages }

    var remoteAvailable: Bool { env.isRemoteAIConfigured && env.repository.settings().hasAIConsent }
    /// Sem servidor configurado na compilação, a opção "Dayli AI" nem aparece.
    var remoteConfigured: Bool { env.isRemoteAIConfigured }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        input = ""
        errorMessage = nil
        pending = nil
        append(role: "user", text: String(text.prefix(1_000)))
        isWorking = true
        defer { isWorking = false }

        // 1–2. Interpretar e montar SOMENTE o contexto permitido.
        let service = env.aiService(preferRemote: mode == .remote)
        if service.kind == .unavailable {
            errorMessage = env.isRemoteAIConfigured ? AIServiceError.consentRequired.localizedDescription : AIServiceError.notConfigured.localizedDescription
            return
        }
        let settings = env.repository.settings()
        let builder = env.dayContextBuilder
        let now = Date.now
        let calendar = Calendar.dayli
        let range = DateInterval(start: calendar.startOfDay(for: now), end: calendar.addingDays(8, to: calendar.startOfDay(for: now)))
        let busy = builder.busy(in: range)
        let pendingTasks = env.repository.pendingTasks()
        // No modo local, nada sai do aparelho: títulos podem ser usados. No remoto, vale a preferência de privacidade.
        let options = service.kind.sendsDataOffDevice
            ? AIContextOptions(shareTitles: settings.aiShareTitles, redactSensitive: true)
            : AIContextOptions(shareTitles: true, redactSensitive: false)
        let payload = AIContextBuilder.build(
            message: text, tasks: pendingTasks.map(\.plannable),
            taskHasTime: Dictionary(uniqueKeysWithValues: pendingTasks.map { ($0.id, $0.hasTime) }),
            busy: busy, routine: env.repository.routine, now: now, timeZone: calendar.timeZone, options: options)

        do {
            // 3. Proposta estruturada.
            let proposal = try await service.propose(for: payload)
            // 4. Validação de horários e regras.
            let validation = AIProposalValidator.validate(proposal, context: AIValidationContext(
                knownTaskIDs: Set(pendingTasks.map(\.id)), busy: busy, now: now, calendar: calendar))
            let json = (try? AIResponseParser.makeEncoder().encode(proposal)) ?? Data()
            let record = AIProposalRecord(proposalJSON: json)
            env.repository.context.insert(record)
            let message = append(role: "assistant", text: validation.message)
            if validation.valid.isEmpty {
                record.status = validation.rejected.isEmpty ? .applied : .rejected
                record.resultSummary = validation.rejected.isEmpty ? "Somente resposta" : "Ações inválidas descartadas"
            } else {
                message.proposal = record
                // 5. Prévia — ações com aviso começam desmarcadas.
                pending = PendingProposal(record: record, result: validation,
                                          selected: Set(validation.valid.filter { $0.warnings.isEmpty }.map(\.id)))
            }
            env.repository.context.saveLogged()
        } catch {
            AppLog.ai.error("Falha no assistente: \(String(describing: type(of: error)), privacy: .public)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AIServiceError.invalidResponse.localizedDescription
        }
    }

    /// 6–8. Confirmação, execução e resultado.
    func confirm() {
        guard let pending else { return }
        let chosen = pending.result.valid.filter { pending.selected.contains($0.id) }
        let outcome = AIProposalExecutor(repository: env.repository).apply(chosen, record: pending.record)
        append(role: "assistant", text: "✅ " + outcome.summary)
        self.pending = nil
        Haptics.success()
    }

    func reject() {
        guard let pending else { return }
        pending.record.status = .rejected
        pending.record.resultSummary = "Rejeitada pela usuária"
        append(role: "assistant", text: "Tudo bem, nada foi alterado.")
        self.pending = nil
    }

    func clearHistory() {
        let context = env.repository.context
        context.delete(conversation)
        let new = AIConversation()
        context.insert(new)
        context.saveLogged()
        conversation = new
        pending = nil
    }

    @discardableResult
    private func append(role: String, text: String) -> AIMessage {
        let message = AIMessage(role: role, text: text)
        env.repository.context.insert(message)
        message.conversation = conversation
        env.repository.context.saveLogged()
        return message
    }
}

struct AssistantView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model: AssistantViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    AssistantContent(model: model)
                } else {
                    LoadingStateView()
                }
            }
            .dayliScreenBackground()
            .navigationTitle("Assistente Dayli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Limpar conversa", role: .destructive) { model?.clearHistory() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .task { if model == nil { model = AssistantViewModel(env: env) } }
    }
}

private struct AssistantContent: View {
    @Bindable var model: AssistantViewModel
    @FocusState private var focused: Bool

    private let suggestions = ["Organize meu dia de amanhã", "Preciso estudar duas horas depois do trabalho",
                               "Quero ir à academia três vezes nesta semana", "Quais compromissos tenho na sexta-feira?",
                               "Não consegui terminar minhas tarefas"]

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty { intro }
                        ForEach(model.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if model.isWorking { LoadingStateView(message: "Pensando com calma…") }
                        if let error = model.errorMessage { InlineNotice(style: .error, message: error) }
                        if model.pending != nil { ProposalReview(model: model).id("proposal") }
                    }
                    .padding(DayliSpacing.screenMargin)
                }
                .onChange(of: model.messages.count) { _, _ in
                    withAnimation {
                        if model.pending != nil {
                            proxy.scrollTo("proposal", anchor: .bottom)
                        } else if let last = model.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            inputBar
        }
    }

    private var modeBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.remoteConfigured {
                Picker("Modo", selection: $model.mode) {
                    ForEach(AssistantViewModel.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Text(model.mode == .local
                 ? "Assistente local: regras no seu iPhone, sem IA generativa e sem enviar dados."
                 : (model.remoteAvailable
                    ? "Dayli AI: o contexto mínimo autorizado é enviado ao servidor do Dayli. Dados sensíveis são removidos."
                    : "Dayli AI indisponível: configure e autorize em Perfil › Inteligência artificial."))
                .font(DayliFont.caption)
                .foregroundStyle(DayliColor.textSecondary)
        }
        .padding(.horizontal, DayliSpacing.screenMargin)
        .padding(.vertical, DayliSpacing.sm)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: DayliSpacing.sm) {
            Text("Como posso ajudar hoje?").font(DayliFont.headlineMedium)
            Text("Nenhuma alteração é feita sem a sua confirmação.").font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
            ForEach(suggestions, id: \.self) { s in
                Button(s) {
                    model.input = s
                    Task { await model.send() }
                }
                .font(DayliFont.bodySmall)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(DayliColor.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(DayliColor.border, lineWidth: 0.5))
                .buttonStyle(.plain)
            }
        }
    }

    private func bubble(_ message: AIMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(DayliFont.bodyMedium)
                .foregroundStyle(message.isUser ? DayliColor.onPrimary : DayliColor.textPrimary)
                .padding(12)
                .background(message.isUser ? DayliColor.primary : DayliColor.surface,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(message.isUser ? .clear : DayliColor.border, lineWidth: 0.5))
                .textSelection(.enabled)
            if !message.isUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((message.isUser ? "Você: " : "Assistente: ") + message.text)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Escreva um pedido…", text: $model.input, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(DayliColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(DayliColor.border, lineWidth: 0.5))
                .accessibilityIdentifier("assistant.input")
            Button {
                Task { await model.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
            .accessibilityLabel("Enviar")
        }
        .padding(.horizontal, DayliSpacing.screenMargin)
        .padding(.vertical, DayliSpacing.sm)
        .background(DayliColor.background)
    }
}

/// Prévia das alterações propostas, com aprovação individual.
private struct ProposalReview: View {
    @Bindable var model: AssistantViewModel

    var body: some View {
        if let pending = model.pending {
            VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                Label("Prévia das alterações", systemImage: "list.bullet.clipboard").font(DayliFont.headlineSmall)
                Text("Revise e escolha o que aplicar. Compromissos existentes não serão alterados.")
                    .font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                ForEach(pending.result.valid) { item in
                    let selected = pending.selected.contains(item.id)
                    Button {
                        if selected { model.pending?.selected.remove(item.id) } else { model.pending?.selected.insert(item.id) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected ? DayliColor.sage : DayliColor.divider)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(describe(item.action)).font(DayliFont.bodyMedium).foregroundStyle(DayliColor.textPrimary)
                                if let rationale = item.action.rationale, !rationale.isEmpty {
                                    Text(rationale).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                                }
                                ForEach(item.warnings, id: \.self) { w in
                                    Text("⚠︎ \(w)").font(DayliFont.caption).foregroundStyle(DayliColor.gentleWarning)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                if !pending.result.rejected.isEmpty {
                    Text("\(pending.result.rejected.count) sugestão(ões) descartada(s) por não passarem na validação.")
                        .font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                }
                HStack {
                    Button("Rejeitar") { model.reject() }.buttonStyle(.dayliSecondary)
                    Button("Confirmar (\(pending.selected.count))") { model.confirm() }
                        .buttonStyle(.dayliPrimary)
                        .disabled(pending.selected.isEmpty)
                        .accessibilityIdentifier("assistant.confirm")
                }
            }
            .dayliCard(elevated: true)
        }
    }

    private func describe(_ action: AIAction) -> String {
        let when: String = action.start.map { "\(DayliFormat.relativeDay($0)) às \(DayliFormat.time($0))" } ?? "sem horário"
        let duration = action.durationMinutes.map { " (\(DayliFormat.duration(minutes: $0)))" } ?? ""
        switch action.type {
        case .createTask: return "Criar tarefa “\(action.title ?? "")” — \(when)\(duration)"
        case .createEvent: return "Criar compromisso “\(action.title ?? "")” — \(when)\(duration)"
        case .rescheduleTask: return "Mover “\(action.title ?? "tarefa")” para \(when)\(duration)"
        case .setTaskPriority: return "Definir prioridade \(action.priority?.title.lowercased() ?? "") para “\(action.title ?? "tarefa")”"
        }
    }
}
