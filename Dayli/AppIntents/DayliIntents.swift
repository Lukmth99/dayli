import AppIntents
import SwiftData
import DayliCore

// App Intents rodam no processo do app e usam o mesmo contêiner SwiftData.
// Nenhuma intenção exclui dados; ações que alteram dados são aditivas e simples
// (criar tarefa, registrar hábito), e o Atalhos pede confirmação quando aplicável.

@MainActor
private func sharedRepository() throws -> DayliRepository {
    let container = try PersistenceController.sharedContainer()
    let repository = DayliRepository(context: container.mainContext)
    return repository
}

/// Atualiza widgets/notificações após mudanças vindas de intents.
@MainActor
private func refreshSideEffects(_ repository: DayliRepository) async {
    let builder = DayContextBuilder(repository: repository, externalEvents: { _ in [] })
    WidgetSnapshotWriter.update(builder: builder, settings: repository.settings())
}

struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Adicionar tarefa"
    static var description = IntentDescription("Adiciona uma tarefa ao Dayli.")

    @Parameter(title: "Título", requestValueDialog: "Qual tarefa você quer adicionar?")
    var taskTitle: String

    @Parameter(title: "Para hoje", default: true)
    var forToday: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Adicionar \(\.$taskTitle) ao Dayli") { \.$forToday }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let title = InputValidator.sanitizedTitle(taskTitle) else {
            throw $taskTitle.needsValueError("Qual é o nome da tarefa?")
        }
        let repository = try sharedRepository()
        let due: Date? = forToday ? Calendar.dayli.startOfDay(for: .now) : nil
        try repository.quickAddTask(title: title, dueDate: due)
        await refreshSideEffects(repository)
        return .result(dialog: "Pronto! “\(title)” foi adicionada\(forToday ? " para hoje" : "").")
    }
}

struct NextActivityIntent: AppIntent {
    static var title: LocalizedStringResource = "Próxima atividade"
    static var description = IntentDescription("Diz qual é o seu próximo compromisso ou tarefa com horário hoje.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repository = try sharedRepository()
        // Eventos do Calendário Apple não são consultados aqui para não exigir permissões neste contexto.
        let builder = DayContextBuilder(repository: repository, externalEvents: { _ in [] })
        let now = Date.now
        let context = builder.context(for: now, now: now)
        let next = context.entries.first { !$0.isAllDay && !$0.isCompleted && ($0.end ?? $0.start) > now }
        guard let next else {
            return .result(dialog: "Você não tem mais atividades com horário hoje. Aproveite o seu ritmo. 🌿")
        }
        let when = next.start <= now ? "agora" : "às \(DayliFormat.time(next.start))"
        return .result(dialog: "Sua próxima atividade é “\(next.title)”, \(when).")
    }
}

struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir agenda de hoje"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.sheet = nil
        AppRouter.shared.selectedTab = .agenda
        return .result()
    }
}

struct OpenPlannerIntent: AppIntent {
    static var title: LocalizedStringResource = "Organizar meu dia"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.selectedTab = .today
        AppRouter.shared.sheet = .planner(.now)
        return .result()
    }
}

// MARK: - Hábitos

struct HabitEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Hábito"
    static var defaultQuery = HabitEntityQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct HabitEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        let repository = try sharedRepository()
        return identifiers.compactMap { repository.habit(id: $0) }.map { HabitEntity(id: $0.id, title: $0.title) }
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        try sharedRepository().activeHabits().map { HabitEntity(id: $0.id, title: $0.title) }
    }
}

struct LogHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar hábito"
    static var description = IntentDescription("Registra que você cumpriu um hábito hoje.")

    @Parameter(title: "Hábito")
    var habit: HabitEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$habit) hoje")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repository = try sharedRepository()
        guard let model = repository.habit(id: habit.id) else {
            return .result(dialog: "Não encontrei esse hábito.")
        }
        repository.log(model, on: .now)
        await refreshSideEffects(repository)
        let count = repository.count(for: model, on: .now)
        let suffix = model.targetCount > 1 ? " (\(count) de \(model.targetCount))" : ""
        return .result(dialog: "Registrado: \(model.title)\(suffix). Muito bem! ✨")
    }
}

struct DayliShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTaskIntent(),
                    phrases: ["Adicionar tarefa no \(.applicationName)", "Nova tarefa no \(.applicationName)"],
                    shortTitle: "Nova tarefa", systemImageName: "plus.circle")
        AppShortcut(intent: NextActivityIntent(),
                    phrases: ["Qual é minha próxima atividade no \(.applicationName)", "Próxima atividade no \(.applicationName)"],
                    shortTitle: "Próxima atividade", systemImageName: "clock")
        AppShortcut(intent: OpenTodayIntent(),
                    phrases: ["Abrir agenda de hoje no \(.applicationName)"],
                    shortTitle: "Agenda de hoje", systemImageName: "calendar")
        AppShortcut(intent: LogHabitIntent(),
                    phrases: ["Registrar \(\.$habit) no \(.applicationName)", "Registrar hábito no \(.applicationName)"],
                    shortTitle: "Registrar hábito", systemImageName: "leaf")
        AppShortcut(intent: OpenPlannerIntent(),
                    phrases: ["Organizar meu dia no \(.applicationName)"],
                    shortTitle: "Organizar meu dia", systemImageName: "sparkles")
    }
}
