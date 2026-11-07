import Foundation
import DayliCore

/// Consolida os dados de um dia (tarefas, compromissos do Dayli e eventos externos)
/// nos tipos do DayliCore usados pela tela Hoje, pelo planejador e pela IA.
@MainActor
struct DayContextBuilder {
    let repository: DayliRepository
    let externalEvents: (DateInterval) -> [ExternalEvent]

    var calendar: Calendar { repository.calendar }

    struct DayContext {
        let day: Date
        let entries: [TimelineEntry]
        let tasks: [TaskItem]
        let busy: [BusyInterval]
        let progress: DailyProgress
        let nextEvent: TimelineEntry?
    }

    func context(for day: Date, now: Date = .now) -> DayContext {
        let interval = calendar.dayInterval(for: day)
        let tasks = repository.tasks(for: day)
        let occurrences = repository.eventOccurrences(in: interval)
        let external = externalEvents(interval)

        let taskEntries = tasks.map { task -> TimelineEntry in
            TimelineEntry(id: "task:\(task.id.uuidString)", kind: .task, sourceID: task.id.uuidString, title: task.title,
                          start: task.hasTime ? (task.dueDate ?? interval.start) : interval.start,
                          end: task.endDate, isAllDay: !task.hasTime, categoryID: task.category?.id,
                          priority: task.priority, isCompleted: task.isCompleted)
        }
        let eventEntries = occurrences.map { occ -> TimelineEntry in
            TimelineEntry(id: occ.id, kind: .event, sourceID: occ.event.id.uuidString, title: occ.event.title,
                          start: occ.start, end: occ.end, isAllDay: occ.event.isAllDay, categoryID: occ.event.category?.id,
                          linkedExternalIdentifier: occ.event.externalEventIdentifier)
        }
        let externalEntries = external.map { ev -> TimelineEntry in
            TimelineEntry(id: "ext:\(ev.id)", kind: .externalEvent, sourceID: ev.eventIdentifier, title: ev.title,
                          start: ev.start, end: ev.end, isAllDay: ev.isAllDay, sourceName: ev.calendarTitle)
        }
        let entries = TimelineBuilder.build(tasks: taskEntries, events: eventEntries, external: externalEntries)
        return DayContext(day: interval.start, entries: entries, tasks: tasks,
                          busy: busyIntervals(from: entries), progress: DailyProgress.from(entries: entries),
                          nextEvent: TimelineBuilder.nextEvent(in: entries, now: now))
    }

    /// Períodos ocupados: compromissos (Dayli e externos) e tarefas pendentes com horário.
    func busyIntervals(from entries: [TimelineEntry]) -> [BusyInterval] {
        entries.compactMap { entry in
            guard !entry.isAllDay, let end = entry.end else { return nil }
            if entry.kind == .task && entry.isCompleted { return nil }
            let id = entry.kind == .task ? "task:\(entry.sourceID)" : entry.id
            return BusyInterval(id: id, title: entry.title, start: entry.start, end: end)
        }
    }

    /// Tarefas candidatas ao planejamento: pendentes, sem horário definido, com prazo até o dia (ou sem data, se prioritárias).
    func plannableTasks(for day: Date) -> [PlannableTask] {
        let dayEnd = calendar.endOfDay(for: day)
        return repository.pendingTasks()
            .filter { task in
                if task.hasTime { return false }
                guard let due = task.dueDate else { return task.priority == .high }
                return due < dayEnd
            }
            .map(\.plannable)
    }

    /// Contexto de vários dias (IA).
    func busy(in range: DateInterval) -> [BusyInterval] {
        var result: [BusyInterval] = []
        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            result += context(for: day).busy
            day = calendar.addingDays(1, to: day)
        }
        return result
    }
}

extension TaskItem {
    var plannable: PlannableTask {
        PlannableTask(id: id, title: title, priority: priority, dueDate: dueDate, estimatedMinutes: estimatedMinutes, area: category?.area)
    }
}
