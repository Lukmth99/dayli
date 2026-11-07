import SwiftUI
import SwiftData
import DayliCore

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        Group {
            if settings?.onboardingCompleted == true {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(colorScheme)
        .tint(DayliColor.primary)
        .task {
            _ = env.repository.settings() // garante o registro de configurações
            await env.notifications.refreshAuthorization()
            await env.synchronizeSideEffects()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            env.calendarService.refreshAuthorization()
            Task {
                await env.notifications.refreshAuthorization()
                await env.synchronizeSideEffects()
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch settings?.appearance ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            TodayView()
                .tabItem { Label("Hoje", systemImage: "sun.max") }
                .tag(AppTab.today)
            AgendaView()
                .tabItem { Label("Agenda", systemImage: "calendar") }
                .tag(AppTab.agenda)
            TasksView()
                .tabItem { Label("Tarefas", systemImage: "checkmark.circle") }
                .tag(AppTab.tasks)
            MyLifeView()
                .tabItem { Label("Minha Vida", systemImage: "square.grid.2x2") }
                .tag(AppTab.myLife)
            ProfileView()
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .quickAdd(let kind):
                QuickAddView(initialKind: kind)
            case .planner(let date):
                PlannerView(day: date)
            case .assistant:
                AssistantView()
            case .review:
                ReviewView()
            }
        }
    }
}

/// Botão "+" de adição rápida, presente na barra de navegação das abas.
struct QuickAddToolbarButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Menu {
            ForEach(QuickAddKind.allCases) { kind in
                Button {
                    router.sheet = .quickAdd(kind)
                } label: {
                    Label(kind.menuTitle, systemImage: kind.symbol)
                }
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DayliColor.primary)
        } primaryAction: {
            router.sheet = .quickAdd(.task)
        }
        .accessibilityLabel("Adicionar")
        .accessibilityHint("Toque para nova tarefa; mantenha pressionado para outras opções")
    }
}
