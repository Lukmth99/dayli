import Foundation

// MARK: - Prioridade

public enum Priority: Int, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    public var id: Int { rawValue }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .low: return "Baixa"
        case .medium: return "Média"
        case .high: return "Alta"
        }
    }
}

// MARK: - Áreas da vida

/// Dimensões da vida usadas no onboarding, nas categorias padrão e em "Minha Vida".
public enum LifeArea: String, Codable, CaseIterable, Sendable, Identifiable {
    case work
    case studies
    case fitness
    case health
    case personal
    case relationship
    case habits

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .work: return "Trabalho"
        case .studies: return "Estudos"
        case .fitness: return "Academia"
        case .health: return "Saúde"
        case .personal: return "Vida pessoal"
        case .relationship: return "Relacionamento"
        case .habits: return "Hábitos"
        }
    }

    public var symbolName: String {
        switch self {
        case .work: return "briefcase"
        case .studies: return "book.closed"
        case .fitness: return "figure.strengthtraining.traditional"
        case .health: return "leaf"
        case .personal: return "heart"
        case .relationship: return "heart.circle"
        case .habits: return "arrow.triangle.2.circlepath"
        }
    }
}

/// Categoria padrão criada na primeira execução. Cores conforme o design system do Stitch.
public struct DefaultCategory: Sendable, Hashable {
    public let name: String
    public let colorHex: String
    public let symbolName: String
    public let area: LifeArea

    public static let all: [DefaultCategory] = [
        DefaultCategory(name: "Trabalho", colorHex: "#9BB8CD", symbolName: "briefcase", area: .work),
        DefaultCategory(name: "Estudos", colorHex: "#B8A3CE", symbolName: "book.closed", area: .studies),
        DefaultCategory(name: "Academia", colorHex: "#A3B8A6", symbolName: "figure.strengthtraining.traditional", area: .fitness),
        DefaultCategory(name: "Pessoal", colorHex: "#D69EAA", symbolName: "heart", area: .personal),
        DefaultCategory(name: "Saúde", colorHex: "#F2C4B7", symbolName: "leaf", area: .health),
        DefaultCategory(name: "Relacionamento", colorHex: "#EDC3CC", symbolName: "heart.circle", area: .relationship)
    ]
}

// MARK: - Horário do dia

/// Horário local (hora/minuto) independente de data. Convertido em `Date`
/// sempre via `Calendar`, o que respeita fuso horário e horário de verão.
public struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public init(minutesSinceMidnight: Int) {
        let clamped = min(max(minutesSinceMidnight, 0), 23 * 60 + 59)
        self.init(hour: clamped / 60, minute: clamped % 60)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    /// Data correspondente a este horário no dia informado. Em dias de transição
    /// de horário de verão, horários inexistentes avançam para o próximo válido.
    public func date(on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            ?? calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(minutesSinceMidnight * 60))
    }

    public static func from(_ date: Date, calendar: Calendar) -> TimeOfDay {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    public var formatted: String { String(format: "%02d:%02d", hour, minute) }
}

public enum DayPeriodPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, morning, afternoon, evening
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "Sem preferência"
        case .morning: return "Manhã"
        case .afternoon: return "Tarde"
        case .evening: return "Noite"
        }
    }
}

// MARK: - Rotina

/// Rotina habitual configurada no onboarding e no perfil.
public struct RoutineSettings: Codable, Hashable, Sendable {
    public var wake: TimeOfDay
    public var sleep: TimeOfDay
    public var workStart: TimeOfDay
    public var workEnd: TimeOfDay
    /// Dias de trabalho no padrão `Calendar` (1 = domingo ... 7 = sábado).
    public var workdays: Set<Int>
    /// Intervalo de respiro entre atividades planejadas automaticamente.
    public var bufferMinutes: Int
    /// Limite de minutos de tarefas pessoais planejadas por dia, para não sobrecarregar.
    public var maxPersonalFocusMinutes: Int
    public var studyPreference: DayPeriodPreference
    public var workoutPreference: DayPeriodPreference

    public init(wake: TimeOfDay = TimeOfDay(hour: 7),
                sleep: TimeOfDay = TimeOfDay(hour: 23),
                workStart: TimeOfDay = TimeOfDay(hour: 9),
                workEnd: TimeOfDay = TimeOfDay(hour: 18),
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                bufferMinutes: Int = 10,
                maxPersonalFocusMinutes: Int = 180,
                studyPreference: DayPeriodPreference = .evening,
                workoutPreference: DayPeriodPreference = .evening) {
        self.wake = wake
        self.sleep = sleep
        self.workStart = workStart
        self.workEnd = workEnd
        self.workdays = workdays
        self.bufferMinutes = bufferMinutes
        self.maxPersonalFocusMinutes = maxPersonalFocusMinutes
        self.studyPreference = studyPreference
        self.workoutPreference = workoutPreference
    }

    public static let `default` = RoutineSettings()

    public func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        workdays.contains(calendar.component(.weekday, from: date))
    }
}

// MARK: - Saudação

public enum Greeting {
    public static func salutation(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Bom dia"
        case 12..<18: return "Boa tarde"
        default: return "Boa noite"
        }
    }

    public static func emoji(for date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return "☀️"
        case 12..<18: return "🌤️"
        default: return "🌙"
        }
    }

    static let messages = [
        "Hoje é um ótimo dia para cuidar dos seus planos.",
        "Um passo de cada vez já é progresso.",
        "Reserve um momento só seu hoje.",
        "Seu ritmo também é uma forma de cuidado.",
        "Pequenas escolhas constroem dias leves.",
        "Respire fundo: você não precisa fazer tudo hoje.",
        "Celebre o que já foi feito, mesmo que pareça pouco."
    ]

    /// Mensagem estável ao longo do dia (muda uma vez por dia).
    public static func message(for date: Date, calendar: Calendar) -> String {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return messages[abs(day) % messages.count]
    }
}

// MARK: - Datas

public extension Calendar {
    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    func dayInterval(for date: Date) -> DateInterval {
        DateInterval(start: startOfDay(for: date), end: endOfDay(for: date))
    }

    func addingDays(_ days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    /// Número de dias de calendário entre duas datas (independente de horário e DST).
    func daysBetween(_ from: Date, _ to: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: from), to: startOfDay(for: to)).day ?? 0
    }
}
