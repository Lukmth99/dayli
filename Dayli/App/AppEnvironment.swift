import Foundation
import SwiftData
import Observation
import DayliCore

enum AppTab: Hashable {
    case today, agenda, tasks, myLife, profile
}

/// Folhas modais globais (adição rápida, planejador, assistente).
enum AppSheet: Identifiable, Equatable {
    case quickAdd(QuickAddKind)
    case planner(Date)
    case assistant
    case review

    var id: String {
        switch self {
        case .quickAdd(let kind): return "quickAdd.\(kind.rawValue)"
        case .planner(let date): return "planner.\(date.timeIntervalSince1970)"
        case .assistant: return "assistant"
        case .review: return "review"
        }
    }
}

enum QuickAddKind: String, CaseIterable, Identifiable {
    case task, event, habit, goal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .task: return "Tarefa"
        case .event: return "Compromisso"
        case .habit: return "Hábito"
        case .goal: return "Meta"
        }
    }
    var menuTitle: String {
        switch self {
        case .task: return "Nova tarefa"
        case .event: return "Novo compromisso"
        case .habit: return "Novo hábito"
        case .goal: return "Nova meta"
        }
    }
    var symbol: String {
        switch self {
        case .task: return "checkmark.circle"
        case .event: return "calendar.badge.plus"
        case .habit: return "leaf"
        case .goal: return "flag"
        }
    }
}

/// Navegação global. Compartilhado com App Intents (que abrem telas específicas).
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var selectedTab: AppTab = .today
    var sheet: AppSheet?
}

/// Dependências do app, injetadas no ambiente SwiftUI.
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let repository: DayliRepository
    let calendarService: CalendarService
    let notifications: NotificationCoordinator
    let router: AppRouter

    /// Incrementado após alterações, para telas que dependem de dados externos se atualizarem.
    private(set) var dataVersion = 0

    private let syncDebouncer = Debouncer(delay: .milliseconds(600))

    init(container: ModelContainer, router: AppRouter? = nil) {
        let router = router ?? AppRouter.shared
        self.container = container
        self.repository = DayliRepository(context: container.mainContext)
        self.calendarService = CalendarService()
        self.notifications = NotificationCoordinator()
        self.router = router
        repository.onChange = { [weak self] in self?.didChangeData() }
        applyCalendarSettings()
    }

    var dayContextBuilder: DayContextBuilder {
        DayContextBuilder(repository: repository, externalEvents: { [calendarService] in calendarService.events(in: $0) })
    }

    func applyCalendarSettings() {
        let settings = repository.settings()
        calendarService.configure(enabled: settings.calendarIntegrationEnabled, visibleCalendarIDs: Set(settings.visibleCalendarIDs))
    }

    /// Chamado após cada alteração persistida: reprograma notificações e widgets (com debounce).
    func didChangeData() {
        dataVersion += 1
        syncDebouncer.schedule { [weak self] in
            await self?.synchronizeSideEffects()
        }
    }

    func synchronizeSideEffects() async {
        let settings = repository.settings()
        guard settings.onboardingCompleted else { return }
        WidgetSnapshotWriter.update(builder: dayContextBuilder, settings: settings)
        await notifications.rebuild(using: repository, external: { [calendarService] in calendarService.events(in: $0) })
    }

    // MARK: IA

    /// Serviço de IA conforme configuração e consentimento.
    func aiService(preferRemote: Bool) -> AIService {
        let settings = repository.settings()
        guard preferRemote else { return LocalRulesAIService() }
        guard settings.hasAIConsent else { return UnavailableAIService() }
        let urlString = settings.aiBackendURL.trimmingCharacters(in: .whitespaces)
        guard !urlString.isEmpty, let url = URL(string: urlString),
              let remote = try? RemoteAIService(baseURL: url, sessionToken: KeychainStore().get(KeychainAccount.aiSessionToken)) else {
            return UnavailableAIService()
        }
        return remote
    }

    var isRemoteAIConfigured: Bool {
        let settings = repository.settings()
        guard let url = URL(string: settings.aiBackendURL), url.scheme?.lowercased() == "https" else { return false }
        return true
    }
}
