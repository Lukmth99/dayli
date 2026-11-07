import Foundation

/// Regra de recorrência simples e previsível (diária, semanal, mensal, anual).
///
/// As ocorrências são calculadas a partir de uma âncora (primeira ocorrência),
/// somando componentes de calendário. Isso preserva o horário local mesmo
/// quando há mudança de horário de verão.
public struct RecurrenceRule: Codable, Hashable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable, Identifiable {
        case daily, weekly, monthly, yearly
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .daily: return "Diariamente"
            case .weekly: return "Semanalmente"
            case .monthly: return "Mensalmente"
            case .yearly: return "Anualmente"
            }
        }
    }

    public var frequency: Frequency
    /// Intervalo (1 = toda semana, 2 = a cada duas semanas...). Sempre ≥ 1.
    public var interval: Int
    /// Somente para `.weekly`. Vazio = mesmo dia da semana da âncora. 1 = domingo ... 7 = sábado.
    public var weekdays: Set<Int>
    /// Último dia (inclusivo) em que pode haver ocorrência.
    public var endDate: Date?

    public init(frequency: Frequency, interval: Int = 1, weekdays: Set<Int> = [], endDate: Date? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.endDate = endDate
    }

    public var summary: String {
        let base: String
        switch frequency {
        case .daily: base = interval == 1 ? "Todos os dias" : "A cada \(interval) dias"
        case .weekly:
            let names = weekdays.sorted().map { Self.shortWeekdayName($0) }
            let days = names.isEmpty ? "" : " (\(names.joined(separator: ", ")))"
            base = (interval == 1 ? "Toda semana" : "A cada \(interval) semanas") + days
        case .monthly: base = interval == 1 ? "Todo mês" : "A cada \(interval) meses"
        case .yearly: base = interval == 1 ? "Todo ano" : "A cada \(interval) anos"
        }
        return base
    }

    public static func shortWeekdayName(_ weekday: Int) -> String {
        ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"][(max(1, min(7, weekday))) - 1]
    }

    // MARK: Ocorrências

    /// Ocorrências dentro de `range` (início inclusivo, fim exclusivo), começando em `anchor`.
    public func occurrences(anchor: Date, in range: DateInterval, calendar: Calendar, limit: Int = 1_000) -> [Date] {
        guard range.end > anchor, limit > 0 else { return [] }
        let lastAllowed = endDate.map { calendar.endOfDay(for: $0) }
        var results: [Date] = []

        func accept(_ date: Date) -> Bool? {
            // nil = parar; true = adicionada; false = ignorada
            if let lastAllowed, date >= lastAllowed { return nil }
            if date >= range.end { return nil }
            if date >= range.start && date >= anchor {
                results.append(date)
                return true
            }
            return false
        }

        switch frequency {
        case .daily, .monthly, .yearly:
            let component: Calendar.Component = frequency == .daily ? .day : (frequency == .monthly ? .month : .year)
            // Pula direto para perto do início do intervalo, evitando iterar desde a âncora.
            var index = 0
            if range.start > anchor {
                let diff = calendar.dateComponents([component], from: anchor, to: range.start).value(for: component) ?? 0
                index = max(0, diff / interval - 1)
            }
            var guardCounter = 0
            while results.count < limit, guardCounter < 100_000 {
                guardCounter += 1
                guard let date = calendar.date(byAdding: component, value: index * interval, to: anchor) else { break }
                if accept(date) == nil { break }
                index += 1
            }

        case .weekly:
            let days = weekdays.isEmpty ? [calendar.component(.weekday, from: anchor)] : weekdays
            let time = TimeOfDay.from(anchor, calendar: calendar)
            guard let anchorWeekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start else { return [] }
            var weekIndex = 0
            if range.start > anchor {
                let diff = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: range.start).weekOfYear ?? 0
                weekIndex = max(0, diff / interval - 1)
            }
            var guardCounter = 0
            outer: while results.count < limit, guardCounter < 20_000 {
                guardCounter += 1
                guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekIndex * interval, to: anchorWeekStart) else { break }
                for offset in 0..<7 {
                    let day = calendar.addingDays(offset, to: weekStart)
                    guard days.contains(calendar.component(.weekday, from: day)) else { continue }
                    let occurrence = time.date(on: day, calendar: calendar)
                    if occurrence < anchor { continue }
                    if accept(occurrence) == nil { break outer }
                    if results.count >= limit { break outer }
                }
                weekIndex += 1
            }
        }
        return results
    }

    /// Próxima ocorrência estritamente após `date`.
    public func nextOccurrence(after date: Date, anchor: Date, calendar: Calendar) -> Date? {
        let start = max(date.addingTimeInterval(1), anchor)
        let horizon = calendar.date(byAdding: .year, value: 5, to: start) ?? start.addingTimeInterval(5 * 365 * 86_400)
        return occurrences(anchor: anchor, in: DateInterval(start: start, end: horizon), calendar: calendar, limit: 1).first
    }
}

/// Regras de recorrência aplicadas a tarefas.
///
/// Política do Dayli: cada ocorrência de uma tarefa recorrente é um registro próprio.
/// Concluir uma ocorrência gera **apenas** a próxima ocorrência, que nasce pendente.
/// As ocorrências futuras nunca são concluídas em conjunto.
public enum TaskRecurrenceEngine {
    /// Data de vencimento da próxima ocorrência após concluir a atual.
    ///
    /// - Se a próxima ocorrência natural ainda estiver no passado (tarefa muito atrasada),
    ///   avança até a primeira ocorrência a partir de hoje, sem gerar um acúmulo de pendências.
    public static func nextDueDate(rule: RecurrenceRule, anchor: Date, currentDue: Date, now: Date, calendar: Calendar) -> Date? {
        guard var next = rule.nextOccurrence(after: currentDue, anchor: anchor, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        if next < today {
            guard let caughtUp = rule.nextOccurrence(after: today.addingTimeInterval(-1), anchor: anchor, calendar: calendar) else { return nil }
            next = caughtUp
        }
        return next
    }
}
