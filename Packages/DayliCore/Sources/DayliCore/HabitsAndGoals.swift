import Foundation

// MARK: - Hábitos

public enum HabitSchedule: Codable, Hashable, Sendable {
    /// Todos os dias.
    case daily
    /// Dias específicos da semana (1 = domingo ... 7 = sábado).
    case weekdays(Set<Int>)
    /// Um número de vezes por semana, em qualquer dia.
    case timesPerWeek(Int)

    public var summary: String {
        switch self {
        case .daily: return "Todos os dias"
        case .weekdays(let days):
            if days.count == 7 { return "Todos os dias" }
            return days.sorted().map(RecurrenceRule.shortWeekdayName).joined(separator: ", ")
        case .timesPerWeek(let n): return n == 1 ? "1 vez por semana" : "\(n) vezes por semana"
        }
    }

    /// Indica se o hábito está programado para o dia. Hábitos semanais (N vezes)
    /// podem ser feitos em qualquer dia, mas nunca "falham" em um dia específico.
    public func isScheduled(on date: Date, calendar: Calendar) -> Bool {
        switch self {
        case .daily, .timesPerWeek: return true
        case .weekdays(let days): return days.contains(calendar.component(.weekday, from: date))
        }
    }
}

public struct HabitStreak: Equatable, Sendable {
    public enum Unit: String, Sendable { case days, weeks }
    public var value: Int
    public var unit: Unit

    public var description: String {
        switch unit {
        case .days: return value == 1 ? "1 dia seguido" : "\(value) dias seguidos"
        case .weeks: return value == 1 ? "1 semana seguida" : "\(value) semanas seguidas"
        }
    }
}

public struct HabitCalculator: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) { self.calendar = calendar }

    /// Normaliza as contagens por dia (início do dia → total registrado).
    public func countsByDay(_ entries: [(date: Date, count: Int)]) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for entry in entries {
            result[calendar.startOfDay(for: entry.date), default: 0] += max(0, entry.count)
        }
        return result
    }

    public func isDayComplete(count: Int, target: Int) -> Bool { count >= max(1, target) }

    /// Sequência atual. Dias não programados são ignorados (não quebram a sequência)
    /// e o dia de hoje ainda pendente também não quebra.
    public func currentStreak(schedule: HabitSchedule, target: Int, counts: [Date: Int], createdAt: Date, today: Date) -> HabitStreak {
        let todayStart = calendar.startOfDay(for: today)
        let firstDay = calendar.startOfDay(for: createdAt)

        if case .timesPerWeek(let perWeek) = schedule {
            let needed = max(1, perWeek)
            var streak = 0
            guard var weekStart = calendar.dateInterval(of: .weekOfYear, for: todayStart)?.start else {
                return HabitStreak(value: 0, unit: .weeks)
            }
            var isCurrentWeek = true
            for _ in 0..<520 {
                let weekEnd = calendar.addingDays(7, to: weekStart)
                if weekEnd <= firstDay { break }
                let done = counts.filter { $0.key >= weekStart && $0.key < weekEnd && isDayComplete(count: $0.value, target: target) }.count
                if done >= needed {
                    streak += 1
                } else if !isCurrentWeek {
                    break
                }
                isCurrentWeek = false
                weekStart = calendar.addingDays(-7, to: weekStart)
            }
            return HabitStreak(value: streak, unit: .weeks)
        }

        var streak = 0
        var day = todayStart
        for _ in 0..<3_660 {
            if day < firstDay { break }
            if schedule.isScheduled(on: day, calendar: calendar) {
                if isDayComplete(count: counts[day] ?? 0, target: target) {
                    streak += 1
                } else if day != todayStart {
                    break
                }
            }
            day = calendar.addingDays(-1, to: day)
        }
        return HabitStreak(value: streak, unit: .days)
    }

    /// Consistência (0...1) nos últimos `days` dias, considerando apenas dias programados.
    public func consistency(schedule: HabitSchedule, target: Int, counts: [Date: Int], createdAt: Date, today: Date, days: Int = 30) -> Double {
        let todayStart = calendar.startOfDay(for: today)
        let firstDay = max(calendar.startOfDay(for: createdAt), calendar.addingDays(-(days - 1), to: todayStart))
        guard firstDay <= todayStart else { return 0 }

        if case .timesPerWeek(let perWeek) = schedule {
            let totalDays = calendar.daysBetween(firstDay, todayStart) + 1
            let expected = max(1.0, Double(max(1, perWeek)) * Double(totalDays) / 7.0)
            let done = counts.filter { $0.key >= firstDay && $0.key <= todayStart && isDayComplete(count: $0.value, target: target) }.count
            return min(1, Double(done) / expected)
        }

        var scheduled = 0
        var done = 0
        var day = firstDay
        while day <= todayStart {
            if schedule.isScheduled(on: day, calendar: calendar) {
                let complete = isDayComplete(count: counts[day] ?? 0, target: target)
                // Hoje só conta se já foi feito (não penaliza o dia em andamento).
                if day != todayStart || complete {
                    scheduled += 1
                    if complete { done += 1 }
                }
            }
            day = calendar.addingDays(1, to: day)
        }
        return scheduled == 0 ? 0 : Double(done) / Double(scheduled)
    }

    /// Progresso na semana corrente: (feitos, esperados).
    public func weekProgress(schedule: HabitSchedule, target: Int, counts: [Date: Int], today: Date) -> (done: Int, expected: Int) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return (0, 0) }
        let done = counts.filter { $0.key >= week.start && $0.key < week.end && isDayComplete(count: $0.value, target: target) }.count
        let expected: Int
        switch schedule {
        case .daily: expected = 7
        case .weekdays(let days): expected = days.count
        case .timesPerWeek(let n): expected = max(1, n)
        }
        return (min(done, expected), expected)
    }
}

// MARK: - Metas

public enum GoalProgressKind: String, Codable, CaseIterable, Sendable, Identifiable {
    /// A usuária informa o valor atual manualmente.
    case manual
    /// Progresso = etapas concluídas / total de etapas.
    case milestones
    /// Progresso = registros de um hábito vinculado no período da meta.
    case linkedHabit

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .manual: return "Manual"
        case .milestones: return "Por etapas"
        case .linkedHabit: return "Hábito vinculado"
        }
    }
}

public enum GoalStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case active, paused, completed, archived
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .active: return "Em andamento"
        case .paused: return "Pausada"
        case .completed: return "Concluída"
        case .archived: return "Arquivada"
        }
    }
}

public enum GoalProgressCalculator {
    /// Fração de progresso (0...1). Nunca mistura tarefas com metas sem vínculo explícito.
    public static func fraction(kind: GoalProgressKind, currentValue: Double, targetValue: Double?,
                                milestonesDone: Int, milestonesTotal: Int, linkedCount: Int) -> Double {
        let raw: Double
        switch kind {
        case .manual:
            guard let target = targetValue, target > 0 else { return 0 }
            raw = currentValue / target
        case .milestones:
            guard milestonesTotal > 0 else { return 0 }
            raw = Double(milestonesDone) / Double(milestonesTotal)
        case .linkedHabit:
            guard let target = targetValue, target > 0 else { return 0 }
            raw = Double(linkedCount) / target
        }
        return min(1, max(0, raw.isFinite ? raw : 0))
    }
}
