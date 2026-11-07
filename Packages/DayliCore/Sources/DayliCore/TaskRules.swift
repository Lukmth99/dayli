import Foundation

/// Filtros da tela Tarefas. São filtros (podem se sobrepor), como no design do Stitch:
/// "Esta semana" inclui "Hoje" e "Próximos dias".
public enum TaskFilter: String, CaseIterable, Sendable, Identifiable {
    case today
    case upcoming
    case thisWeek
    case later
    case noDate
    case completed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "Hoje"
        case .upcoming: return "Próximos dias"
        case .thisWeek: return "Esta semana"
        case .later: return "Mais adiante"
        case .noDate: return "Sem data"
        case .completed: return "Concluídas"
        }
    }

    /// - today: vence hoje ou ficou pendente de dias anteriores.
    /// - upcoming: de amanhã até daqui a 3 dias.
    /// - thisWeek: pendências até 6 dias à frente (inclui hoje e atrasadas).
    /// - later: além de 6 dias.
    public func matches(dueDate: Date?, isCompleted: Bool, now: Date, calendar: Calendar) -> Bool {
        if self == .completed { return isCompleted }
        if isCompleted { return false }
        guard let due = dueDate else { return self == .noDate }
        let offset = calendar.daysBetween(now, due)
        switch self {
        case .today: return offset <= 0
        case .upcoming: return (1...3).contains(offset)
        case .thisWeek: return offset <= 6
        case .later: return offset > 6
        case .noDate, .completed: return false
        }
    }
}

public enum TaskSort: String, CaseIterable, Sendable, Identifiable {
    case dueDate, priority, title, created
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .dueDate: return "Data"
        case .priority: return "Prioridade"
        case .title: return "Título"
        case .created: return "Criação"
        }
    }
}

public enum TaskTiming {
    /// Uma tarefa está pendente de dias anteriores quando seu dia já passou.
    /// Tarefas com horário só ficam "atrasadas" depois do horário.
    public static func isOverdue(dueDate: Date?, hasTime: Bool, isCompleted: Bool, now: Date, calendar: Calendar) -> Bool {
        guard !isCompleted, let due = dueDate else { return false }
        if hasTime { return due < now }
        return due < calendar.startOfDay(for: now)
    }

    /// Rótulo gentil para pendências (sem linguagem negativa).
    public static func gentleOverdueLabel(dueDate: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.daysBetween(dueDate, now)
        switch days {
        case ..<1: return "Ainda dá tempo hoje"
        case 1: return "Ficou de ontem"
        default: return "Aguardando há \(days) dias"
        }
    }

    /// Nova data ao reagendar para "amanhã", preservando o horário quando houver.
    public static func rescheduledToTomorrow(dueDate: Date?, hasTime: Bool, now: Date, calendar: Calendar) -> Date {
        let tomorrow = calendar.addingDays(1, to: calendar.startOfDay(for: now))
        guard hasTime, let due = dueDate else { return tomorrow }
        return TimeOfDay.from(due, calendar: calendar).date(on: tomorrow, calendar: calendar)
    }
}

/// Validação de entrada compartilhada (formulários, App Intents e IA).
public enum InputValidator {
    public static let maxTitleLength = 200
    public static let maxNotesLength = 5_000

    /// Remove caracteres de controle e espaços excedentes. Retorna nil se ficar vazio.
    public static func sanitizedTitle(_ raw: String) -> String? {
        let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(maxTitleLength))
    }

    public static func sanitizedNotes(_ raw: String) -> String {
        let cleaned = String(raw.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) })
        return String(cleaned.prefix(maxNotesLength))
    }

    public static func isValidEventRange(start: Date, end: Date) -> Bool { end > start }

    public static func clampDuration(_ minutes: Int) -> Int { min(max(minutes, 5), 12 * 60) }
}
