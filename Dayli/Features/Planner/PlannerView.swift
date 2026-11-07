import SwiftUI
import DayliCore

/// "Organizar meu dia": planejamento determinístico, local e offline.
/// Mostra uma prévia; nada é alterado até a usuária aprovar.
/// Compromissos existentes nunca são movidos.
struct PlannerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State var day: Date
    @State private var plan: DayPlan?
    @State private var approved: Set<UUID> = []
    @State private var adjustedStarts: [UUID: Date] = [:]
    @State private var resultMessage: String?

    init(day: Date) {
        _day = State(initialValue: Calendar.dayli.startOfDay(for: day))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Dia", selection: $day, in: Calendar.dayli.startOfDay(for: .now)..., displayedComponents: .date)
                        .onChange(of: day) { _, _ in compute() }
                } footer: {
                    Text("Consideramos suas tarefas pendentes sem horário, prioridades, prazos, duração estimada, compromissos, horário de trabalho e de descanso.")
                }

                if let resultMessage {
                    Section { InlineNotice(style: .info, message: resultMessage) }
                }

                if let plan {
                    if !plan.conflicts.isEmpty {
                        Section("Conflitos existentes") {
                            ForEach(Array(plan.conflicts.enumerated()), id: \.offset) { _, pair in
                                Label("\(pair.first.title) × \(pair.second.title)", systemImage: "exclamationmark.triangle")
                                    .font(DayliFont.bodySmall)
                                    .foregroundStyle(DayliColor.gentleWarning)
                            }
                        }
                    }

                    Section {
                        if plan.suggestions.isEmpty {
                            Text("Nenhuma sugestão para este dia.")
                                .foregroundStyle(DayliColor.textSecondary)
                        }
                        ForEach(plan.suggestions) { suggestion in
                            suggestionRow(suggestion)
                        }
                    } header: {
                        Text("Sugestões (\(approved.count) de \(plan.suggestions.count) selecionadas)")
                    } footer: {
                        if plan.freeMinutesRemaining > 0 {
                            Text("Ainda sobram cerca de \(DayliFormat.duration(minutes: plan.freeMinutesRemaining)) livres — tempo para descansar também é plano.")
                        }
                    }

                    if !plan.unplanned.isEmpty {
                        Section("Ficaram para depois") {
                            ForEach(plan.unplanned) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    Text(item.reason).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                                }
                            }
                        }
                    }
                } else {
                    LoadingStateView(message: "Organizando com calma…")
                }

                Section {
                    Button {
                        dismiss()
                        router.sheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            router.sheet = .assistant
                        }
                    } label: {
                        Label("Pedir ajuda ao assistente", systemImage: "sparkles")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .dayliScreenBackground()
            .navigationTitle("Organizar meu dia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar", action: apply)
                        .fontWeight(.semibold)
                        .disabled(approved.isEmpty)
                        .accessibilityIdentifier("planner.apply")
                }
            }
            .onAppear { if plan == nil { compute() } }
        }
    }

    private func suggestionRow(_ suggestion: PlannedSuggestion) -> some View {
        let isOn = approved.contains(suggestion.taskID)
        let duration = suggestion.end.timeIntervalSince(suggestion.start)
        let start = adjustedStarts[suggestion.taskID] ?? suggestion.start
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Button {
                    Haptics.selection()
                    if isOn { approved.remove(suggestion.taskID) } else { approved.insert(suggestion.taskID) }
                } label: {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? DayliColor.sage : DayliColor.divider)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOn ? "Aprovada" : "Rejeitada")
                .accessibilityHint("Toque duas vezes para alternar")
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title).font(DayliFont.bodyLarge.weight(.medium))
                    Text("\(DayliFormat.time(start)) – \(DayliFormat.time(start.addingTimeInterval(duration))) · \(suggestion.reason)")
                        .font(DayliFont.caption)
                        .foregroundStyle(DayliColor.textSecondary)
                }
            }
            if isOn {
                DatePicker("Ajustar início", selection: Binding(
                    get: { start },
                    set: { adjustedStarts[suggestion.taskID] = $0 }), displayedComponents: .hourAndMinute)
                    .font(DayliFont.bodySmall)
                if let warning = adjustmentWarning(for: suggestion, start: start, duration: duration) {
                    InlineNotice(style: .warning, message: warning)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Ao ajustar um horário, avisa se passou a conflitar com algo ocupado.
    private func adjustmentWarning(for suggestion: PlannedSuggestion, start: Date, duration: TimeInterval) -> String? {
        guard adjustedStarts[suggestion.taskID] != nil else { return nil }
        let builder = env.dayContextBuilder
        let busy = builder.context(for: day).busy
        let candidate = DateInterval(start: start, end: start.addingTimeInterval(duration))
        let clashes = ConflictDetector.conflicts(for: candidate, excludingID: "task:\(suggestion.taskID.uuidString)", in: busy)
        return clashes.isEmpty ? nil : "Este horário conflita com \(clashes.map(\.title).prefix(2).joined(separator: ", "))."
    }

    private func compute() {
        let builder = env.dayContextBuilder
        let context = builder.context(for: day)
        let tasks = builder.plannableTasks(for: day)
        let result = DayPlanner(calendar: .dayli).plan(day: day, tasks: tasks, busy: context.busy, routine: env.repository.routine, now: .now)
        plan = result
        approved = Set(result.suggestions.map(\.taskID))
        adjustedStarts = [:]
    }

    private func apply() {
        guard let plan else { return }
        var count = 0
        for suggestion in plan.suggestions where approved.contains(suggestion.taskID) {
            guard let task = env.repository.task(id: suggestion.taskID), !task.isCompleted else { continue }
            let start = adjustedStarts[suggestion.taskID] ?? suggestion.start
            let movedToAnotherDay = task.dueDate.map { !Calendar.dayli.isDate($0, inSameDayAs: start) } ?? false
            env.repository.reschedule(task, to: start, hasTime: true, countsAsReschedule: movedToAnotherDay)
            count += 1
        }
        Haptics.success()
        resultMessage = count == 1 ? "1 tarefa foi encaixada no seu dia." : "\(count) tarefas foram encaixadas no seu dia."
        compute()
    }
}
