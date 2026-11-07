import Foundation
import SwiftData
import DayliCore

struct EventDraft: Equatable {
    var title = ""
    var start: Date
    var end: Date
    var isAllDay = false
    var location = ""
    var notes = ""
    var categoryID: UUID?
    var recurrence: RecurrenceRule?
    var alertOffsetMinutes: Int? = 15
    /// Espelhar no Calendário Apple (requer permissão).
    var mirrorToCalendarID: String?

    init(start: Date = .now, calendar: Calendar = .dayli) {
        let rounded = calendar.nextDate(after: start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? start
        self.start = rounded
        self.end = rounded.addingTimeInterval(3_600)
    }

    init(event: CalendarEvent) {
        title = event.title
        start = event.start
        end = event.end
        isAllDay = event.isAllDay
        location = event.location
        notes = event.notes
        categoryID = event.category?.id
        recurrence = event.recurrence
        alertOffsetMinutes = event.alertOffsetMinutes
        mirrorToCalendarID = event.externalCalendarIdentifier
    }
}

/// Ocorrência concreta de um compromisso do Dayli (expande recorrências).
struct EventOccurrence: Identifiable, Hashable {
    let event: CalendarEvent
    let start: Date
    let end: Date
    var id: String { "event:\(event.id.uuidString)@\(Int(start.timeIntervalSince1970))" }

    static func == (lhs: EventOccurrence, rhs: EventOccurrence) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension DayliRepository {
    func allEvents() -> [CalendarEvent] {
        (try? context.fetch(FetchDescriptor<CalendarEvent>(sortBy: [SortDescriptor(\.start)]))) ?? []
    }

    func event(id: UUID) -> CalendarEvent? {
        var descriptor = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Ocorrências dos compromissos do Dayli no intervalo.
    func eventOccurrences(in range: DateInterval) -> [EventOccurrence] {
        let rangeEnd = range.end
        // Pré-filtro no banco: eventos que começam antes do fim do intervalo.
        let descriptor = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.start < rangeEnd })
        let events = (try? context.fetch(descriptor)) ?? []
        return events.flatMap { event in
            event.occurrenceStarts(in: range, calendar: calendar).map {
                EventOccurrence(event: event, start: $0, end: $0.addingTimeInterval(event.duration))
            }
        }
        .sorted { $0.start < $1.start }
    }

    @discardableResult
    func createEvent(from draft: EventDraft) throws -> CalendarEvent {
        guard let title = InputValidator.sanitizedTitle(draft.title) else { throw RepositoryError.invalidTitle }
        let (start, end) = normalizedRange(draft)
        guard InputValidator.isValidEventRange(start: start, end: end) else { throw RepositoryError.invalidDateRange }
        let event = CalendarEvent(title: title, start: start, end: end)
        context.insert(event)
        apply(draft, to: event, title: title, start: start, end: end)
        guard commit() else { throw RepositoryError.saveFailed }
        return event
    }

    func updateEvent(_ event: CalendarEvent, from draft: EventDraft) throws {
        guard let title = InputValidator.sanitizedTitle(draft.title) else { throw RepositoryError.invalidTitle }
        let (start, end) = normalizedRange(draft)
        guard InputValidator.isValidEventRange(start: start, end: end) else { throw RepositoryError.invalidDateRange }
        apply(draft, to: event, title: title, start: start, end: end)
        guard commit() else { throw RepositoryError.saveFailed }
    }

    private func normalizedRange(_ draft: EventDraft) -> (Date, Date) {
        guard draft.isAllDay else { return (draft.start, draft.end) }
        let start = calendar.startOfDay(for: draft.start)
        let endDay = max(calendar.startOfDay(for: draft.end), start)
        return (start, calendar.endOfDay(for: endDay))
    }

    private func apply(_ draft: EventDraft, to event: CalendarEvent, title: String, start: Date, end: Date) {
        event.title = title
        event.start = start
        event.end = end
        event.isAllDay = draft.isAllDay
        event.location = String(InputValidator.sanitizedNotes(draft.location).prefix(200))
        event.notes = InputValidator.sanitizedNotes(draft.notes)
        event.category = draft.categoryID.flatMap { id in categories().first { $0.id == id } }
        event.recurrence = draft.recurrence
        event.alertOffsetMinutes = draft.alertOffsetMinutes
        event.updatedAt = now()
    }

    func linkExternal(_ event: CalendarEvent, eventIdentifier: String?, calendarIdentifier: String?) {
        event.externalEventIdentifier = eventIdentifier
        event.externalCalendarIdentifier = calendarIdentifier
        commit()
    }

    func delete(_ event: CalendarEvent) {
        context.delete(event)
        commit()
    }

    /// Compromissos que conflitam com o intervalo informado (Dayli + externos).
    func conflicts(start: Date, end: Date, excluding eventID: UUID?, external: [ExternalEvent]) -> [BusyInterval] {
        guard end > start else { return [] }
        let candidate = DateInterval(start: start, end: end)
        let window = DateInterval(start: calendar.startOfDay(for: start), end: calendar.endOfDay(for: end))
        var busy = eventOccurrences(in: window)
            .filter { $0.event.id != eventID && !$0.event.isAllDay }
            .compactMap { BusyInterval(id: $0.id, title: $0.event.title, start: $0.start, end: $0.end) }
        let linkedID = eventID.flatMap { event(id: $0)?.externalEventIdentifier }
        busy += external.filter { !$0.isAllDay && $0.eventIdentifier != linkedID }
            .compactMap { BusyInterval(id: "ext:\($0.id)", title: $0.title, start: $0.start, end: $0.end) }
        return ConflictDetector.conflicts(for: candidate, in: busy)
    }
}
