import Foundation
import EventKit
import Observation
import DayliCore

/// Evento lido do Calendário Apple. É apenas uma referência — o Dayli não o persiste.
struct ExternalEvent: Identifiable, Hashable {
    /// Identificador único por ocorrência (eventos recorrentes compartilham `eventIdentifier`).
    let id: String
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendarIdentifier: String
    let calendarTitle: String
    let calendarColorHex: String
    let isEditable: Bool
}

struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    let allowsModifications: Bool
    let sourceTitle: String
}

enum CalendarAccessState: Equatable {
    case notDetermined, fullAccess, writeOnly, denied, restricted

    var description: String {
        switch self {
        case .notDetermined: return "Não configurado"
        case .fullAccess: return "Acesso completo"
        case .writeOnly: return "Somente adicionar eventos"
        case .denied: return "Acesso negado"
        case .restricted: return "Restrito pelo sistema"
        }
    }

    var canRead: Bool { self == .fullAccess }
    var canWrite: Bool { self == .fullAccess || self == .writeOnly }
}

enum CalendarServiceError: LocalizedError {
    case noAccess
    case calendarNotFound
    case eventNotFound
    case readOnlyCalendar

    var errorDescription: String? {
        switch self {
        case .noAccess: return "O Dayli não tem permissão para acessar o Calendário. Você pode alterar isso nos Ajustes do iPhone."
        case .calendarNotFound: return "O calendário escolhido não está mais disponível."
        case .eventNotFound: return "O evento não foi encontrado no Calendário."
        case .readOnlyCalendar: return "Este calendário não permite alterações."
        }
    }
}

/// Integração com EventKit respeitando permissões negadas, revogadas e acesso somente de escrita.
@MainActor
@Observable
final class CalendarService {
    private(set) var accessState: CalendarAccessState = .notDetermined
    /// Incrementado quando o banco de eventos do sistema muda (para as telas recarregarem).
    private(set) var changeToken = 0

    private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var cache: [String: [ExternalEvent]] = [:]

    /// Calendários visíveis (vazio = todos). Definido a partir das configurações.
    @ObservationIgnored var visibleCalendarIDs: Set<String> = []
    /// A integração só lê eventos quando a usuária a ativa nas configurações.
    @ObservationIgnored var isEnabled = false

    /// Aplica as preferências da usuária e avisa as telas para recarregarem.
    func configure(enabled: Bool, visibleCalendarIDs ids: Set<String>) {
        guard enabled != isEnabled || ids != visibleCalendarIDs else { return }
        isEnabled = enabled
        visibleCalendarIDs = ids
        cache.removeAll()
        changeToken += 1
    }

    init() {
        refreshAuthorization()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.cache.removeAll()
                self?.refreshAuthorization()
                self?.changeToken += 1
            }
        }
    }

    func refreshAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let newState: CalendarAccessState
        switch status {
        case .fullAccess: newState = .fullAccess
        case .writeOnly: newState = .writeOnly
        case .denied: newState = .denied
        case .restricted: newState = .restricted
        case .notDetermined: newState = .notDetermined
        case .authorized: newState = .fullAccess // legado (< iOS 17)
        @unknown default: newState = .denied
        }
        if newState != accessState {
            accessState = newState
            cache.removeAll()
        }
    }

    /// Solicita acesso completo. Só deve ser chamado após a usuária tocar em "Conectar calendário".
    @discardableResult
    func requestFullAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshAuthorization()
            changeToken += 1
            return granted
        } catch {
            AppLog.calendar.error("Falha ao solicitar acesso ao calendário")
            refreshAuthorization()
            return false
        }
    }

    func calendars() -> [CalendarInfo] {
        guard accessState.canRead else { return [] }
        return store.calendars(for: .event).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, colorHex: $0.cgColor.map(Self.hex) ?? "#9BB8CD",
                         allowsModifications: $0.allowsContentModifications, sourceTitle: $0.source.title)
        }
        .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    func writableCalendars() -> [CalendarInfo] { calendars().filter(\.allowsModifications) }

    /// Eventos externos no intervalo. Retorna vazio sem permissão de leitura ou se desativado.
    func events(in range: DateInterval) -> [ExternalEvent] {
        guard isEnabled, accessState.canRead else { return [] }
        let key = "\(range.start.timeIntervalSince1970)-\(range.end.timeIntervalSince1970)-\(visibleCalendarIDs.sorted().joined(separator: ","))"
        if let cached = cache[key] { return cached }

        let allCalendars = store.calendars(for: .event)
        let selected = visibleCalendarIDs.isEmpty ? allCalendars : allCalendars.filter { visibleCalendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: selected)
        let result = store.events(matching: predicate).compactMap { event -> ExternalEvent? in
            guard let identifier = event.eventIdentifier, let start = event.startDate, let end = event.endDate else { return nil }
            return ExternalEvent(id: "\(identifier)@\(Int(start.timeIntervalSince1970))", eventIdentifier: identifier,
                                 title: event.title ?? "Sem título", start: start, end: end, isAllDay: event.isAllDay,
                                 location: event.location, calendarIdentifier: event.calendar.calendarIdentifier,
                                 calendarTitle: event.calendar.title, calendarColorHex: event.calendar.cgColor.map(Self.hex) ?? "#9BB8CD",
                                 isEditable: event.calendar.allowsContentModifications)
        }
        if cache.count > 50 { cache.removeAll() }
        cache[key] = result
        return result
    }

    /// Cria ou atualiza no Calendário Apple o espelho de um compromisso do Dayli.
    /// Retorna o `eventIdentifier` resultante.
    func upsertMirror(of event: CalendarEvent, calendarID: String) throws -> String {
        guard accessState.canWrite else { throw CalendarServiceError.noAccess }
        let ekEvent: EKEvent
        if let identifier = event.externalEventIdentifier, accessState.canRead, let existing = store.event(withIdentifier: identifier) {
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: store)
        }
        if ekEvent.calendar == nil || ekEvent.calendar.calendarIdentifier != calendarID {
            guard let calendar = store.calendar(withIdentifier: calendarID) ?? store.defaultCalendarForNewEvents else {
                throw CalendarServiceError.calendarNotFound
            }
            guard calendar.allowsContentModifications else { throw CalendarServiceError.readOnlyCalendar }
            ekEvent.calendar = calendar
        }
        ekEvent.title = event.title
        ekEvent.startDate = event.start
        ekEvent.endDate = event.end
        ekEvent.isAllDay = event.isAllDay
        ekEvent.location = event.location.isEmpty ? nil : event.location
        ekEvent.notes = event.notes.isEmpty ? nil : event.notes
        ekEvent.recurrenceRules = event.recurrence.map { [Self.ekRule(from: $0)] }
        try store.save(ekEvent, span: .futureEvents, commit: true)
        cache.removeAll()
        return ekEvent.eventIdentifier ?? ""
    }

    /// Remove um evento do Calendário Apple. Deve ser chamado somente após confirmação explícita.
    func deleteExternalEvent(identifier: String) throws {
        guard accessState.canRead else { throw CalendarServiceError.noAccess }
        guard let event = store.event(withIdentifier: identifier) else { throw CalendarServiceError.eventNotFound }
        guard event.calendar.allowsContentModifications else { throw CalendarServiceError.readOnlyCalendar }
        try store.remove(event, span: .thisEvent, commit: true)
        cache.removeAll()
    }

    // MARK: Conversões

    private static func ekRule(from rule: RecurrenceRule) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        let days = rule.frequency == .weekly && !rule.weekdays.isEmpty
            ? rule.weekdays.sorted().compactMap { EKWeekday(rawValue: $0).map { EKRecurrenceDayOfWeek($0) } }
            : nil
        let end = rule.endDate.map { EKRecurrenceEnd(end: Calendar.dayli.endOfDay(for: $0).addingTimeInterval(-1)) }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: rule.interval, daysOfTheWeek: days, daysOfTheMonth: nil,
                                monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }

    private static func hex(_ color: CGColor) -> String {
        guard let components = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return "#9BB8CD" }
        return String(format: "#%02X%02X%02X", Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))
    }
}
