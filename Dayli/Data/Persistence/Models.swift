import Foundation
import SwiftData
import DayliCore

// MARK: - Convenções
//
// • Todo modelo tem `id: UUID` estável e único.
// • Enums são persistidos pelo rawValue e expostos via propriedades computadas,
//   para que adicionar casos no futuro não quebre dados existentes.
// • Estruturas Codable (recorrência, agenda de hábito, rotina) são persistidas como `Data`
//   para controle explícito de versão.
// • Eventos de calendários externos NÃO são persistidos aqui: são lidos ao vivo via EventKit.
//   O Dayli guarda apenas o identificador do espelho dos compromissos que ele mesmo criou.
// • Nomes: `TaskItem` evita conflito com `Swift.Task`; `LifeCategory` evita conflito com
//   o typedef `Category` do runtime Objective-C.

private let codingEncoder = JSONEncoder()
private let codingDecoder = JSONDecoder()

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date

    init(id: UUID = UUID(), name: String = "", photoData: Data? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.photoData = photoData
        self.createdAt = createdAt
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "D" : letters.joined()
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Automático"
        case .light: return "Claro"
        case .dark: return "Escuro"
        }
    }
}

/// Configurações gerais. Inclui as preferências de lembretes (ReminderPreference do
/// escopo original foi incorporado aqui para evitar um modelo 1:1 redundante).
@Model
final class AppSettings {
    @Attribute(.unique) var id: UUID
    var onboardingCompleted: Bool
    var appearanceRaw: String
    var selectedAreasRaw: [String]

    // Notificações
    var notificationsEnabled: Bool
    var taskRemindersEnabled: Bool
    var eventAlertsEnabled: Bool
    var habitRemindersEnabled: Bool
    var deadlineAlertsEnabled: Bool
    var morningSummaryEnabled: Bool
    var morningSummaryMinutes: Int
    var eveningReviewEnabled: Bool
    var eveningReviewMinutes: Int
    var defaultTaskReminderOffset: Int
    var defaultEventAlertOffset: Int
    var quietHoursEnabled: Bool
    var quietStartMinutes: Int
    var quietEndMinutes: Int
    var mutedCategoryIDs: [UUID]

    // Calendário
    var calendarIntegrationEnabled: Bool
    var visibleCalendarIDs: [String]
    var defaultExportCalendarID: String?

    // Privacidade e IA
    var aiEnabled: Bool
    var aiConsentDate: Date?
    var aiShareTitles: Bool
    var aiBackendURL: String
    var widgetHideDetails: Bool

    init(id: UUID = UUID()) {
        self.id = id
        onboardingCompleted = false
        appearanceRaw = AppearancePreference.system.rawValue
        selectedAreasRaw = LifeArea.allCases.map(\.rawValue)
        notificationsEnabled = false
        taskRemindersEnabled = true
        eventAlertsEnabled = true
        habitRemindersEnabled = true
        deadlineAlertsEnabled = true
        morningSummaryEnabled = true
        morningSummaryMinutes = 7 * 60 + 30
        eveningReviewEnabled = true
        eveningReviewMinutes = 21 * 60 + 30
        defaultTaskReminderOffset = 15
        defaultEventAlertOffset = 15
        quietHoursEnabled = true
        quietStartMinutes = 22 * 60 + 30
        quietEndMinutes = 7 * 60
        mutedCategoryIDs = []
        calendarIntegrationEnabled = false
        visibleCalendarIDs = []
        defaultExportCalendarID = nil
        aiEnabled = false
        aiConsentDate = nil
        aiShareTitles = false
        aiBackendURL = ""
        widgetHideDetails = false
    }

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var selectedAreas: Set<LifeArea> {
        get { Set(selectedAreasRaw.compactMap(LifeArea.init(rawValue:))) }
        set { selectedAreasRaw = newValue.map(\.rawValue).sorted() }
    }

    var quietHours: QuietHours? {
        guard quietHoursEnabled else { return nil }
        return QuietHours(start: TimeOfDay(minutesSinceMidnight: quietStartMinutes), end: TimeOfDay(minutesSinceMidnight: quietEndMinutes))
    }

    var hasAIConsent: Bool { aiEnabled && aiConsentDate != nil }
}

@Model
final class RoutinePreference {
    @Attribute(.unique) var id: UUID
    var routineData: Data
    var updatedAt: Date

    init(id: UUID = UUID(), routine: RoutineSettings = .default) {
        self.id = id
        self.routineData = (try? codingEncoder.encode(routine)) ?? Data()
        self.updatedAt = .now
    }

    var routine: RoutineSettings {
        get { (try? codingDecoder.decode(RoutineSettings.self, from: routineData)) ?? .default }
        set {
            routineData = (try? codingEncoder.encode(newValue)) ?? routineData
            updatedAt = .now
        }
    }
}

@Model
final class LifeCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var symbolName: String
    var areaRaw: String?
    var isDefault: Bool
    var sortOrder: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.category) var tasks: [TaskItem] = []
    @Relationship(deleteRule: .nullify, inverse: \CalendarEvent.category) var events: [CalendarEvent] = []
    @Relationship(deleteRule: .nullify, inverse: \Habit.category) var habits: [Habit] = []
    @Relationship(deleteRule: .nullify, inverse: \Goal.category) var goals: [Goal] = []

    init(id: UUID = UUID(), name: String, colorHex: String, symbolName: String, area: LifeArea?, isDefault: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.areaRaw = area?.rawValue
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    var area: LifeArea? {
        get { areaRaw.flatMap(LifeArea.init(rawValue:)) }
        set { areaRaw = newValue?.rawValue }
    }
}

enum TaskStatus: String, Codable {
    case pending, completed
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var priorityRaw: Int
    var createdAt: Date
    var updatedAt: Date
    /// Data (e horário, se `hasTime`) de vencimento.
    var dueDate: Date?
    var hasTime: Bool
    var estimatedMinutes: Int
    var completedAt: Date?
    var statusRaw: String
    /// Minutos de antecedência do lembrete. nil = sem lembrete.
    var reminderOffsetMinutes: Int?
    var recurrenceData: Data?
    /// Âncora da série recorrente (primeira ocorrência).
    var recurrenceAnchor: Date?
    /// Identifica todas as ocorrências da mesma série recorrente.
    var seriesID: UUID?
    var rescheduleCount: Int
    /// Quando esta ocorrência foi gerada automaticamente ao concluir outra.
    var generatedFromTaskID: UUID?
    var isDemo: Bool
    var category: LifeCategory?
    @Relationship(deleteRule: .cascade, inverse: \Subtask.task) var subtasks: [Subtask] = []

    init(id: UUID = UUID(), title: String, notes: String = "", priority: Priority = .medium, dueDate: Date? = nil, hasTime: Bool = false,
         estimatedMinutes: Int = 30, category: LifeCategory? = nil, reminderOffsetMinutes: Int? = nil, recurrence: RecurrenceRule? = nil, isDemo: Bool = false) {
        let timestamp = Date.now
        self.id = id
        self.title = title
        self.notes = notes
        self.priorityRaw = priority.rawValue
        self.createdAt = timestamp
        self.updatedAt = timestamp
        self.generatedFromTaskID = nil
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.estimatedMinutes = estimatedMinutes
        self.completedAt = nil
        self.statusRaw = TaskStatus.pending.rawValue
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.recurrenceData = recurrence.flatMap { try? codingEncoder.encode($0) }
        self.recurrenceAnchor = recurrence == nil ? nil : dueDate
        self.seriesID = recurrence == nil ? nil : UUID()
        self.rescheduleCount = 0
        self.isDemo = isDemo
        self.category = category
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var isCompleted: Bool { status == .completed }

    var recurrence: RecurrenceRule? {
        get { recurrenceData.flatMap { try? codingDecoder.decode(RecurrenceRule.self, from: $0) } }
        set {
            recurrenceData = newValue.flatMap { try? codingEncoder.encode($0) }
            if newValue != nil {
                if seriesID == nil { seriesID = UUID() }
                if recurrenceAnchor == nil { recurrenceAnchor = dueDate }
            } else {
                recurrenceAnchor = nil
            }
        }
    }

    var sortedSubtasks: [Subtask] { subtasks.sorted { $0.order < $1.order } }

    var endDate: Date? {
        guard hasTime, let dueDate else { return nil }
        return dueDate.addingTimeInterval(TimeInterval(estimatedMinutes * 60))
    }
}

@Model
final class Subtask {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    var order: Int
    var task: TaskItem?

    init(id: UUID = UUID(), title: String, isDone: Bool = false, order: Int = 0) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.order = order
    }
}

/// Compromisso criado no Dayli. Pode ser espelhado no Calendário Apple
/// (`externalEventIdentifier`), mas o registro mestre é do Dayli.
@Model
final class CalendarEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var notes: String
    var recurrenceData: Data?
    /// Minutos antes para o alerta. nil = sem alerta.
    var alertOffsetMinutes: Int?
    var externalEventIdentifier: String?
    var externalCalendarIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var isDemo: Bool
    var category: LifeCategory?

    init(id: UUID = UUID(), title: String, start: Date, end: Date, isAllDay: Bool = false, location: String = "", notes: String = "",
         category: LifeCategory? = nil, recurrence: RecurrenceRule? = nil, alertOffsetMinutes: Int? = 15, isDemo: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.recurrenceData = recurrence.flatMap { try? codingEncoder.encode($0) }
        self.alertOffsetMinutes = alertOffsetMinutes
        self.createdAt = .now
        self.updatedAt = .now
        self.isDemo = isDemo
        self.category = category
    }

    var recurrence: RecurrenceRule? {
        get { recurrenceData.flatMap { try? codingDecoder.decode(RecurrenceRule.self, from: $0) } }
        set { recurrenceData = newValue.flatMap { try? codingEncoder.encode($0) } }
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// Inícios das ocorrências dentro do intervalo (inclui eventos não recorrentes).
    func occurrenceStarts(in range: DateInterval, calendar: Calendar) -> [Date] {
        if let rule = recurrence {
            // Inclui ocorrências que começaram antes do intervalo mas ainda estão em andamento.
            let extended = DateInterval(start: range.start.addingTimeInterval(-duration), end: range.end)
            return rule.occurrences(anchor: start, in: extended, calendar: calendar)
                .filter { $0.addingTimeInterval(duration) > range.start }
        }
        return (start < range.end && end > range.start) ? [start] : []
    }
}

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var title: String
    var symbolName: String
    var colorHex: String
    var scheduleData: Data
    /// Quantidade por dia para considerar o dia cumprido (ex.: 8 copos). Mínimo 1.
    var targetCount: Int
    var unit: String
    var reminderMinutes: Int?
    var createdAt: Date
    var isArchived: Bool
    var isDemo: Bool
    var category: LifeCategory?
    @Relationship(deleteRule: .cascade, inverse: \HabitEntry.habit) var entries: [HabitEntry] = []
    @Relationship(deleteRule: .nullify, inverse: \Goal.linkedHabit) var linkedGoals: [Goal] = []

    init(id: UUID = UUID(), title: String, symbolName: String = "sparkles", colorHex: String = "#A3B8A6", schedule: HabitSchedule = .daily,
         targetCount: Int = 1, unit: String = "", reminderMinutes: Int? = nil, category: LifeCategory? = nil, isDemo: Bool = false) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.scheduleData = (try? codingEncoder.encode(schedule)) ?? Data()
        self.targetCount = max(1, targetCount)
        self.unit = unit
        self.reminderMinutes = reminderMinutes
        self.createdAt = .now
        self.isArchived = false
        self.isDemo = isDemo
        self.category = category
    }

    var schedule: HabitSchedule {
        get { (try? codingDecoder.decode(HabitSchedule.self, from: scheduleData)) ?? .daily }
        set { scheduleData = (try? codingEncoder.encode(newValue)) ?? scheduleData }
    }
}

@Model
final class HabitEntry {
    @Attribute(.unique) var id: UUID
    /// Início do dia (no calendário local) ao qual o registro pertence.
    var day: Date
    var count: Int
    var createdAt: Date
    var habit: Habit?

    init(id: UUID = UUID(), day: Date, count: Int = 1) {
        self.id = id
        self.day = day
        self.count = count
        self.createdAt = .now
    }
}

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var startDate: Date
    var endDate: Date
    var progressKindRaw: String
    var targetValue: Double?
    var currentValue: Double
    var unit: String
    var statusRaw: String
    var createdAt: Date
    var isDemo: Bool
    var category: LifeCategory?
    var linkedHabit: Habit?
    @Relationship(deleteRule: .cascade, inverse: \GoalMilestone.goal) var milestones: [GoalMilestone] = []

    init(id: UUID = UUID(), title: String, details: String = "", startDate: Date, endDate: Date, progressKind: GoalProgressKind = .manual,
         targetValue: Double? = nil, currentValue: Double = 0, unit: String = "", category: LifeCategory? = nil, isDemo: Bool = false) {
        self.id = id
        self.title = title
        self.details = details
        self.startDate = startDate
        self.endDate = endDate
        self.progressKindRaw = progressKind.rawValue
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.unit = unit
        self.statusRaw = GoalStatus.active.rawValue
        self.createdAt = .now
        self.isDemo = isDemo
        self.category = category
    }

    var progressKind: GoalProgressKind {
        get { GoalProgressKind(rawValue: progressKindRaw) ?? .manual }
        set { progressKindRaw = newValue.rawValue }
    }

    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var sortedMilestones: [GoalMilestone] { milestones.sorted { $0.order < $1.order } }

    /// Registros do hábito vinculado dentro do período da meta (apenas vínculo explícito).
    func linkedCount(calendar: Calendar) -> Int {
        guard progressKind == .linkedHabit, let habit = linkedHabit else { return 0 }
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.endOfDay(for: endDate)
        return habit.entries.filter { $0.day >= start && $0.day < end && $0.count >= habit.targetCount }.count
    }

    func progress(calendar: Calendar) -> Double {
        GoalProgressCalculator.fraction(kind: progressKind, currentValue: currentValue, targetValue: targetValue,
                                        milestonesDone: milestones.filter(\.isDone).count, milestonesTotal: milestones.count,
                                        linkedCount: linkedCount(calendar: calendar))
    }
}

@Model
final class GoalMilestone {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    var dueDate: Date?
    var order: Int
    var goal: Goal?

    init(id: UUID = UUID(), title: String, isDone: Bool = false, dueDate: Date? = nil, order: Int = 0) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.dueDate = dueDate
        self.order = order
    }
}

@Model
final class AIConversation {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \AIMessage.conversation) var messages: [AIMessage] = []

    init(id: UUID = UUID()) {
        self.id = id
        self.createdAt = .now
    }

    var sortedMessages: [AIMessage] { messages.sorted { $0.createdAt < $1.createdAt } }
}

@Model
final class AIMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var text: String
    var createdAt: Date
    var conversation: AIConversation?
    var proposal: AIProposalRecord?

    init(id: UUID = UUID(), role: String, text: String) {
        self.id = id
        self.roleRaw = role
        self.text = text
        self.createdAt = .now
    }

    var isUser: Bool { roleRaw == "user" }
}

enum AIProposalStatus: String {
    case pending, applied, partiallyApplied, rejected, failed
}

/// Registro auditável de cada proposta da IA e do que foi efetivamente aplicado.
@Model
final class AIProposalRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var proposalJSON: Data
    var statusRaw: String
    var appliedActionIDs: [UUID]
    var resultSummary: String
    @Relationship(deleteRule: .nullify, inverse: \AIMessage.proposal) var message: AIMessage?

    init(id: UUID = UUID(), proposalJSON: Data) {
        self.id = id
        self.createdAt = .now
        self.proposalJSON = proposalJSON
        self.statusRaw = AIProposalStatus.pending.rawValue
        self.appliedActionIDs = []
        self.resultSummary = ""
    }

    var status: AIProposalStatus {
        get { AIProposalStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var proposal: AIProposal? { try? AIResponseParser.parse(proposalJSON) }
}
