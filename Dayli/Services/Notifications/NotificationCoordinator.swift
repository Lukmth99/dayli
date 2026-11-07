import Foundation
import UserNotifications
import Observation
import DayliCore

/// Reconstrói todas as notificações locais a partir dos dados persistidos.
///
/// Estratégia: identificadores determinísticos + reconstrução completa (com debounce)
/// após qualquer alteração. Isso evita duplicidades, garante que itens editados ou
/// excluídos sejam reprogramados/removidos e respeita o limite de 64 pendentes do iOS.
/// O iOS pode atrasar ou agrupar notificações; o app não promete entrega exata.
@MainActor
@Observable
final class NotificationCoordinator {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var lastScheduledCount = 0

    private let center = UNUserNotificationCenter.current()
    private let calendar: Calendar
    /// Horizonte de planejamento das notificações não repetitivas.
    private let horizonDays = 7

    static let managedPrefixes = ["task.", "event.", "habit.", "digest.", "deadline."]

    init(calendar: Calendar = .dayli) {
        self.calendar = calendar
    }

    func refreshAuthorization() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// Solicita permissão. Chamado somente a partir de uma ação explícita da usuária.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    /// Recalcula e substitui todas as notificações gerenciadas pelo Dayli.
    func rebuild(using repository: DayliRepository, external: (DateInterval) -> [ExternalEvent]) async {
        await refreshAuthorization()
        let settings = repository.settings()
        guard isAuthorized, settings.notificationsEnabled else {
            await removeAllManaged()
            lastScheduledCount = 0
            return
        }

        let now = repository.now()
        let planned = plan(repository: repository, settings: settings, now: now, external: external)
        let finalized = NotificationPlanner.finalize(planned, quietHours: settings.quietHours, now: now, calendar: calendar)

        await removeAllManaged()
        for item in finalized {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.threadIdentifier = item.kind.rawValue
            // .timeSensitive exige entitlement específico; usamos .active (respeita Foco e Resumo Programado).
            content.interruptionLevel = .active
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            } catch {
                AppLog.notifications.error("Falha ao agendar notificação do tipo \(item.kind.rawValue, privacy: .public)")
            }
        }
        lastScheduledCount = finalized.count
    }

    private func removeAllManaged() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { id in Self.managedPrefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: Planejamento

    private func plan(repository: DayliRepository, settings: AppSettings, now: Date, external: (DateInterval) -> [ExternalEvent]) -> [PlannedNotification] {
        var items: [PlannedNotification] = []
        let horizon = DateInterval(start: now, end: calendar.addingDays(horizonDays, to: now))
        let muted = Set(settings.mutedCategoryIDs)

        // Tarefas
        if settings.taskRemindersEnabled || settings.deadlineAlertsEnabled {
            for task in repository.pendingTasks() {
                guard let due = task.dueDate else { continue }
                if let categoryID = task.category?.id, muted.contains(categoryID) { continue }
                if settings.taskRemindersEnabled, let offset = task.reminderOffsetMinutes {
                    let base = task.hasTime ? due : TimeOfDay(hour: 9).date(on: due, calendar: calendar)
                    let fire = base.addingTimeInterval(TimeInterval(-offset * 60))
                    if horizon.includes(fire) {
                        let body = task.hasTime ? "Às \(DayliFormat.time(due)). Sem pressa, no seu ritmo." : "Está na sua lista de hoje."
                        items.append(PlannedNotification(id: "task.\(task.id.uuidString)", kind: .task, title: task.title, body: body, fireDate: fire))
                    }
                }
                if settings.deadlineAlertsEnabled, task.priority == .high, !task.hasTime {
                    // Aviso de prazo na véspera, às 18h, para tarefas prioritárias.
                    let eve = TimeOfDay(hour: 18).date(on: calendar.addingDays(-1, to: due), calendar: calendar)
                    if horizon.includes(eve) {
                        items.append(PlannedNotification(id: "deadline.\(task.id.uuidString)", kind: .deadline, title: "Prazo amanhã",
                                                         body: "\(task.title) vence amanhã. Quer reservar um horário?", fireDate: eve))
                    }
                }
            }
        }

        // Compromissos do Dayli
        if settings.eventAlertsEnabled {
            for occ in repository.eventOccurrences(in: horizon) {
                guard let offset = occ.event.alertOffsetMinutes, !occ.event.isAllDay else { continue }
                if let categoryID = occ.event.category?.id, muted.contains(categoryID) { continue }
                // Se espelhado no Calendário Apple, o próprio Calendário também pode alertar; mantemos o alerta do Dayli
                // somente quando o espelho não existe, para não duplicar.
                if occ.event.externalEventIdentifier != nil { continue }
                let fire = occ.start.addingTimeInterval(TimeInterval(-offset * 60))
                let place = occ.event.location.isEmpty ? "" : " · \(occ.event.location)"
                items.append(PlannedNotification(id: "event.\(occ.id)", kind: .event, title: occ.event.title,
                                                 body: "Começa às \(DayliFormat.time(occ.start))\(place)", fireDate: fire,
                                                 bypassesQuietHours: false))
            }
        }

        // Hábitos (próximos dias em que estão programados)
        if settings.habitRemindersEnabled {
            for habit in repository.activeHabits() {
                guard let minutes = habit.reminderMinutes else { continue }
                if let categoryID = habit.category?.id, muted.contains(categoryID) { continue }
                for offset in 0..<horizonDays {
                    let day = calendar.addingDays(offset, to: calendar.startOfDay(for: now))
                    guard habit.schedule.isScheduled(on: day, calendar: calendar) else { continue }
                    if repository.count(for: habit, on: day) >= habit.targetCount { continue }
                    let fire = TimeOfDay(minutesSinceMidnight: minutes).date(on: day, calendar: calendar)
                    items.append(PlannedNotification(id: "habit.\(habit.id.uuidString).\(offset)", kind: .habit, title: habit.title,
                                                     body: "Um pequeno passo pelo seu bem-estar.", fireDate: fire))
                }
            }
        }

        // Resumo matinal e revisão noturna
        for offset in 0..<horizonDays {
            let day = calendar.addingDays(offset, to: calendar.startOfDay(for: now))
            if settings.morningSummaryEnabled {
                let count = repository.tasks(for: day).filter { !$0.isCompleted }.count
                let events = repository.eventOccurrences(in: calendar.dayInterval(for: day)).count + external(calendar.dayInterval(for: day)).count
                let body: String
                if count == 0 && events == 0 {
                    body = "Seu dia está livre por enquanto. Que tal planejar com calma?"
                } else {
                    body = "Você tem \(count) \(count == 1 ? "tarefa" : "tarefas") e \(events) \(events == 1 ? "compromisso" : "compromissos") hoje."
                }
                items.append(PlannedNotification(id: "digest.morning.\(offset)", kind: .morningSummary, title: "Bom dia ☀️", body: body,
                                                 fireDate: TimeOfDay(minutesSinceMidnight: settings.morningSummaryMinutes).date(on: day, calendar: calendar)))
            }
            if settings.eveningReviewEnabled {
                items.append(PlannedNotification(id: "digest.evening.\(offset)", kind: .eveningReview, title: "Revisão do dia 🌙",
                                                 body: "Veja o que foi feito e deixe amanhã organizado.",
                                                 fireDate: TimeOfDay(minutesSinceMidnight: settings.eveningReviewMinutes).date(on: day, calendar: calendar)))
            }
        }
        return items
    }
}
