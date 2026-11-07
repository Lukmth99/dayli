import Foundation

// MARK: - Planejamento de notificações (regras puras)

public struct QuietHours: Codable, Hashable, Sendable {
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    /// Suporta intervalos que atravessam a meia-noite (ex.: 22:00–07:00).
    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let minutes = TimeOfDay.from(date, calendar: calendar).minutesSinceMidnight
        let s = start.minutesSinceMidnight, e = end.minutesSinceMidnight
        if s == e { return false }
        return s < e ? (minutes >= s && minutes < e) : (minutes >= s || minutes < e)
    }

    /// Fim do período de silêncio que contém `date`.
    public func endOfQuiet(after date: Date, calendar: Calendar) -> Date {
        let todayEnd = end.date(on: date, calendar: calendar)
        if todayEnd > date { return todayEnd }
        return end.date(on: calendar.addingDays(1, to: date), calendar: calendar)
    }
}

public struct PlannedNotification: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case task, event, habit, morningSummary, eveningReview, deadline }

    /// Identificador determinístico — reprogramar substitui em vez de duplicar.
    public var id: String
    public var kind: Kind
    public var title: String
    public var body: String
    public var fireDate: Date
    /// Notificações essenciais (compromissos) podem tocar no horário de silêncio? Não por padrão.
    public var bypassesQuietHours: Bool

    public init(id: String, kind: Kind, title: String, body: String, fireDate: Date, bypassesQuietHours: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.bypassesQuietHours = bypassesQuietHours
    }
}

public enum NotificationPlanner {
    /// O iOS mantém no máximo 64 notificações locais pendentes por app. Reservamos margem.
    public static let systemLimit = 60

    /// Remove passadas, duplicadas, aplica horário de silêncio e respeita o limite do sistema
    /// (mantendo as mais próximas).
    public static func finalize(_ items: [PlannedNotification], quietHours: QuietHours?, now: Date, calendar: Calendar, limit: Int = systemLimit) -> [PlannedNotification] {
        var seen = Set<String>()
        var result: [PlannedNotification] = []
        for var item in items {
            guard seen.insert(item.id).inserted else { continue }
            if let quietHours, !item.bypassesQuietHours, quietHours.contains(item.fireDate, calendar: calendar) {
                item.fireDate = quietHours.endOfQuiet(after: item.fireDate, calendar: calendar)
            }
            guard item.fireDate > now else { continue }
            result.append(item)
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(max(0, limit)))
    }
}

// MARK: - Snapshot para widgets

/// Dados mínimos compartilhados com a extensão de widgets via App Group.
/// Quando `hideDetails` é verdadeiro, títulos são substituídos por rótulos neutros
/// (widgets aparecem na tela bloqueada).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var start: Date?
        public var end: Date?
        public var colorHex: String?
        public var isTask: Bool
        public var isCompleted: Bool
        public var priority: Priority?

        public init(id: String, title: String, start: Date?, end: Date?, colorHex: String?, isTask: Bool, isCompleted: Bool, priority: Priority?) {
            self.id = id
            self.title = title
            self.start = start
            self.end = end
            self.colorHex = colorHex
            self.isTask = isTask
            self.isCompleted = isCompleted
            self.priority = priority
        }
    }

    public var generatedAt: Date
    public var day: Date
    public var events: [Item]
    public var priorityTasks: [Item]
    public var totalTasks: Int
    public var completedTasks: Int
    public var hideDetails: Bool

    public init(generatedAt: Date, day: Date, events: [Item], priorityTasks: [Item], totalTasks: Int, completedTasks: Int, hideDetails: Bool) {
        self.generatedAt = generatedAt
        self.day = day
        self.events = events
        self.priorityTasks = priorityTasks
        self.totalTasks = totalTasks
        self.completedTasks = completedTasks
        self.hideDetails = hideDetails
    }

    public static let empty = WidgetSnapshot(generatedAt: .distantPast, day: .distantPast, events: [], priorityTasks: [], totalTasks: 0, completedTasks: 0, hideDetails: false)

    public var progress: DailyProgress { DailyProgress(total: totalTasks, completed: completedTasks) }

    public func nextEvent(at date: Date) -> Item? {
        events.filter { ($0.end ?? $0.start ?? .distantPast) > date }.min { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    public func upcomingEvents(at date: Date, limit: Int) -> [Item] {
        Array(events.filter { ($0.end ?? $0.start ?? .distantPast) > date }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
            .prefix(limit))
    }

    /// Momentos em que o conteúdo do widget muda (início/fim de eventos).
    public func transitionDates(after date: Date) -> [Date] {
        let dates = events.flatMap { [$0.start, $0.end].compactMap { $0 } }.filter { $0 > date }
        return Array(Set(dates)).sorted()
    }

    public func displayTitle(for item: Item) -> String {
        hideDetails ? (item.isTask ? "Tarefa" : "Compromisso") : item.title
    }
}

public enum WidgetSnapshotStore {
    public static let fileName = "widget-snapshot.json"

    public static func url(in container: URL) -> URL { container.appendingPathComponent(fileName) }

    public static func write(_ snapshot: WidgetSnapshot, to container: URL) throws {
        let data = try AIResponseParser.makeEncoder().encode(snapshot)
        #if canImport(Darwin)
        try data.write(to: url(in: container), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        // Windows/Linux (apenas para rodar os testes do núcleo fora do macOS).
        try data.write(to: url(in: container), options: [.atomic])
        #endif
    }

    public static func read(from container: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url(in: container)) else { return nil }
        return try? AIResponseParser.makeDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
