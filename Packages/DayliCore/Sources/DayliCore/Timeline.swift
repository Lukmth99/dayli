import Foundation

/// Item exibido na linha do tempo da tela Hoje e na Agenda.
public struct TimelineEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Tarefa do Dayli (pode ser concluída).
        case task
        /// Compromisso criado no Dayli.
        case event
        /// Evento de um calendário externo (somente referência, não pertence ao Dayli).
        case externalEvent
    }

    public var id: String
    public var kind: Kind
    /// Identificador do registro de origem (UUID do Dayli ou `eventIdentifier` do EventKit).
    public var sourceID: String
    public var title: String
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var categoryID: UUID?
    public var priority: Priority?
    public var isCompleted: Bool
    /// Para eventos do Dayli espelhados no calendário Apple: identificador do evento externo.
    public var linkedExternalIdentifier: String?
    /// Nome do calendário de origem, para eventos externos.
    public var sourceName: String?

    public init(id: String, kind: Kind, sourceID: String, title: String, start: Date, end: Date? = nil,
                isAllDay: Bool = false, categoryID: UUID? = nil, priority: Priority? = nil,
                isCompleted: Bool = false, linkedExternalIdentifier: String? = nil, sourceName: String? = nil) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.categoryID = categoryID
        self.priority = priority
        self.isCompleted = isCompleted
        self.linkedExternalIdentifier = linkedExternalIdentifier
        self.sourceName = sourceName
    }

    /// Apenas tarefas são concluíveis. Eventos de calendário apenas "acontecem".
    public var isCompletable: Bool { kind == .task }

    public var interval: DateInterval? {
        guard let end, end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

public enum TimelineBuilder {
    /// Combina tarefas com horário, compromissos do Dayli e eventos externos,
    /// removendo eventos externos que são espelhos de compromissos do Dayli.
    public static func build(tasks: [TimelineEntry], events: [TimelineEntry], external: [TimelineEntry]) -> [TimelineEntry] {
        let mirrored = Set(events.compactMap(\.linkedExternalIdentifier))
        var seenExternal = Set<String>()
        let filteredExternal = external.filter { entry in
            guard !mirrored.contains(entry.sourceID) else { return false }
            // Um mesmo evento pode vir de consultas sobrepostas: dedup por id.
            return seenExternal.insert(entry.id).inserted
        }
        return (tasks + events + filteredExternal).sorted(by: order)
    }

    static func order(_ a: TimelineEntry, _ b: TimelineEntry) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        if a.kind != b.kind { return rank(a.kind) < rank(b.kind) }
        return a.title.localizedCompare(b.title) == .orderedAscending
    }

    private static func rank(_ kind: TimelineEntry.Kind) -> Int {
        switch kind {
        case .event: return 0
        case .externalEvent: return 1
        case .task: return 2
        }
    }

    /// Próximo compromisso (evento) que ainda não terminou.
    public static func nextEvent(in entries: [TimelineEntry], now: Date) -> TimelineEntry? {
        entries
            .filter { $0.kind != .task && !$0.isAllDay && ($0.end ?? $0.start) > now }
            .min { $0.start < $1.start }
    }
}

// MARK: - Progresso diário

/// Progresso diário calculado **somente** a partir de tarefas elegíveis.
/// Eventos de calendário não contam como "concluídos".
public struct DailyProgress: Equatable, Sendable {
    public let total: Int
    public let completed: Int

    public init(total: Int, completed: Int) {
        self.total = max(0, total)
        self.completed = min(max(0, completed), max(0, total))
    }

    public var pending: Int { total - completed }

    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    public var percent: Int { Int((fraction * 100).rounded()) }

    public static func from(entries: [TimelineEntry]) -> DailyProgress {
        let tasks = entries.filter(\.isCompletable)
        return DailyProgress(total: tasks.count, completed: tasks.filter(\.isCompleted).count)
    }
}
