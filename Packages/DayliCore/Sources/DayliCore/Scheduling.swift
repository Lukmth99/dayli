import Foundation

/// Período ocupado (compromisso, tarefa com horário, evento externo).
public struct BusyInterval: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var interval: DateInterval

    public init(id: String, title: String, interval: DateInterval) {
        self.id = id
        self.title = title
        self.interval = interval
    }

    public init?(id: String, title: String, start: Date, end: Date) {
        guard end > start else { return nil }
        self.init(id: id, title: title, interval: DateInterval(start: start, end: end))
    }
}

public struct ConflictPair: Hashable, Sendable {
    public let first: BusyInterval
    public let second: BusyInterval
}

public enum ConflictDetector {
    /// Sobreposição estrita: intervalos que apenas se tocam (fim == início) não conflitam.
    public static func overlaps(_ a: DateInterval, _ b: DateInterval) -> Bool {
        a.start < b.end && b.start < a.end
    }

    public static func conflicts(for candidate: DateInterval, excludingID: String? = nil, in busy: [BusyInterval]) -> [BusyInterval] {
        busy.filter { $0.id != excludingID && overlaps($0.interval, candidate) }
    }

    /// Todos os pares conflitantes (O(n log n) + pares reais).
    public static func allConflicts(_ items: [BusyInterval]) -> [ConflictPair] {
        let sorted = items.sorted { $0.interval.start < $1.interval.start }
        var pairs: [ConflictPair] = []
        for i in sorted.indices {
            var j = i + 1
            while j < sorted.count, sorted[j].interval.start < sorted[i].interval.end {
                pairs.append(ConflictPair(first: sorted[i], second: sorted[j]))
                j += 1
            }
        }
        return pairs
    }
}

public enum FreeSlotFinder {
    /// Une intervalos sobrepostos ou adjacentes.
    public static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// Janelas livres dentro de `window`, considerando um respiro (`buffer`) em volta dos períodos ocupados.
    public static func freeSlots(in window: DateInterval, busy: [DateInterval], buffer: TimeInterval = 0, minimumDuration: TimeInterval = 0) -> [DateInterval] {
        let expanded = busy.map { DateInterval(start: $0.start.addingTimeInterval(-buffer), end: $0.end.addingTimeInterval(buffer)) }
        var slots: [DateInterval] = []
        var cursor = window.start
        for block in merge(expanded) {
            if block.end <= cursor { continue }
            if block.start >= window.end { break }
            if block.start > cursor {
                slots.append(DateInterval(start: cursor, end: min(block.start, window.end)))
            }
            cursor = max(cursor, block.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end {
            slots.append(DateInterval(start: cursor, end: window.end))
        }
        return slots.filter { $0.duration >= max(minimumDuration, 1) }
    }
}

// MARK: - Planejador determinístico ("Organizar meu dia")

public struct PlannableTask: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var priority: Priority
    public var dueDate: Date?
    public var estimatedMinutes: Int
    public var area: LifeArea?

    public init(id: UUID, title: String, priority: Priority, dueDate: Date?, estimatedMinutes: Int, area: LifeArea?) {
        self.id = id
        self.title = title
        self.priority = priority
        self.dueDate = dueDate
        self.estimatedMinutes = estimatedMinutes
        self.area = area
    }
}

public struct PlannedSuggestion: Hashable, Sendable, Identifiable {
    public var id: UUID { taskID }
    public var taskID: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var reason: String
}

public struct UnplannedTask: Hashable, Sendable, Identifiable {
    public var id: UUID { taskID }
    public var taskID: UUID
    public var title: String
    public var reason: String
}

public struct DayPlan: Sendable {
    public var day: Date
    public var suggestions: [PlannedSuggestion]
    public var unplanned: [UnplannedTask]
    public var conflicts: [ConflictPair]
    public var freeMinutesRemaining: Int
}

public struct DayPlanner: Sendable {
    public var calendar: Calendar
    /// Granularidade dos horários sugeridos, em minutos.
    public var slotGranularity: Int

    public init(calendar: Calendar = .current, slotGranularity: Int = 5) {
        self.calendar = calendar
        self.slotGranularity = max(1, slotGranularity)
    }

    /// Ordenação: atrasadas → vencem no dia → prioridade → prazo → duração.
    public func sortForPlanning(_ tasks: [PlannableTask], day: Date) -> [PlannableTask] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.endOfDay(for: day)
        func bucket(_ t: PlannableTask) -> Int {
            guard let due = t.dueDate else { return 2 }
            if due < dayStart { return 0 }
            if due < dayEnd { return 1 }
            return 2
        }
        return tasks.sorted { a, b in
            let ba = bucket(a), bb = bucket(b)
            if ba != bb { return ba < bb }
            if a.priority != b.priority { return a.priority > b.priority }
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if a.estimatedMinutes != b.estimatedMinutes { return a.estimatedMinutes < b.estimatedMinutes }
            return a.title.localizedCompare(b.title) == .orderedAscending
        }
    }

    public func plan(day: Date, tasks: [PlannableTask], busy: [BusyInterval], routine: RoutineSettings, now: Date) -> DayPlan {
        let dayStart = calendar.startOfDay(for: day)
        var windowStart = routine.wake.date(on: dayStart, calendar: calendar)
        var windowEnd = routine.sleep.date(on: dayStart, calendar: calendar)
        if windowEnd <= windowStart {
            // Dorme depois da meia-noite: a janela termina no dia seguinte.
            windowEnd = routine.sleep.date(on: calendar.addingDays(1, to: dayStart), calendar: calendar)
        }
        // Não sugerir horários no passado.
        if now > windowStart { windowStart = roundUp(now) }

        let conflicts = ConflictDetector.allConflicts(busy)
        guard windowStart < windowEnd else {
            return DayPlan(day: dayStart, suggestions: [],
                           unplanned: tasks.map { UnplannedTask(taskID: $0.id, title: $0.title, reason: "O dia já está terminando. Que tal deixar para amanhã?") },
                           conflicts: conflicts, freeMinutesRemaining: 0)
        }
        let window = DateInterval(start: windowStart, end: windowEnd)
        let buffer = TimeInterval(max(0, routine.bufferMinutes) * 60)
        let busyIntervals = busy.map(\.interval)

        var workSlots: [DateInterval] = []
        var personalBusy = busyIntervals
        if routine.isWorkday(dayStart, calendar: calendar) {
            let ws = routine.workStart.date(on: dayStart, calendar: calendar)
            let we = routine.workEnd.date(on: dayStart, calendar: calendar)
            if we > ws {
                let work = DateInterval(start: ws, end: we)
                if let workInWindow = work.intersection(with: window), workInWindow.duration > 0 {
                    workSlots = FreeSlotFinder.freeSlots(in: workInWindow, busy: busyIntervals, buffer: buffer)
                }
                personalBusy.append(work)
            }
        }
        var personalSlots = FreeSlotFinder.freeSlots(in: window, busy: personalBusy, buffer: buffer)

        var suggestions: [PlannedSuggestion] = []
        var unplanned: [UnplannedTask] = []
        var personalMinutesUsed = 0

        for task in sortForPlanning(tasks, day: dayStart) {
            let minutes = min(max(task.estimatedMinutes, 5), 8 * 60)
            let duration = TimeInterval(minutes * 60)
            let isWork = task.area == .work && !workSlots.isEmpty

            if !isWork && personalMinutesUsed + minutes > routine.maxPersonalFocusMinutes {
                unplanned.append(UnplannedTask(taskID: task.id, title: task.title,
                                               reason: "Deixamos fora para preservar seu descanso hoje."))
                continue
            }

            let placed: DateInterval?
            if isWork {
                placed = allocate(duration: duration, buffer: buffer, in: &workSlots)
            } else {
                placed = allocate(duration: duration, buffer: buffer, in: &personalSlots)
            }

            guard let slot = placed else {
                unplanned.append(UnplannedTask(taskID: task.id, title: task.title,
                                               reason: "Não encontramos um horário livre com \(minutes) min neste dia."))
                continue
            }
            if !isWork { personalMinutesUsed += minutes }
            suggestions.append(PlannedSuggestion(taskID: task.id, title: task.title, start: slot.start, end: slot.end,
                                                 reason: reason(for: task, dayStart: dayStart)))
        }

        let remaining = (workSlots + personalSlots).reduce(0) { $0 + Int($1.duration / 60) }
        return DayPlan(day: dayStart, suggestions: suggestions.sorted { $0.start < $1.start },
                       unplanned: unplanned, conflicts: conflicts, freeMinutesRemaining: remaining)
    }

    private func reason(for task: PlannableTask, dayStart: Date) -> String {
        if let due = task.dueDate, due < dayStart { return "Ficou de outro dia — encaixamos com calma." }
        if let due = task.dueDate, due < calendar.endOfDay(for: dayStart) { return "Prazo hoje." }
        switch task.priority {
        case .high: return "Prioridade alta."
        case .medium: return "Prioridade média."
        case .low: return "Encaixe leve em um horário livre."
        }
    }

    /// Primeiro encaixe possível; consome o espaço usado (mais o respiro) da janela.
    private func allocate(duration: TimeInterval, buffer: TimeInterval, in slots: inout [DateInterval]) -> DateInterval? {
        for index in slots.indices {
            let slot = slots[index]
            let start = roundUp(slot.start)
            let end = start.addingTimeInterval(duration)
            guard end <= slot.end else { continue }
            let newStart = end.addingTimeInterval(buffer)
            if newStart < slot.end {
                slots[index] = DateInterval(start: newStart, end: slot.end)
            } else {
                slots.remove(at: index)
            }
            return DateInterval(start: start, end: end)
        }
        return nil
    }

    func roundUp(_ date: Date) -> Date {
        let granularity = TimeInterval(slotGranularity * 60)
        let seconds = date.timeIntervalSinceReferenceDate
        let rounded = (seconds / granularity).rounded(.up) * granularity
        return Date(timeIntervalSinceReferenceDate: rounded)
    }
}
