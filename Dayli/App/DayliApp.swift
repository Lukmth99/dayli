import SwiftUI
import SwiftData
import DayliCore

@main
@MainActor
struct DayliApp: App {
    @State private var environment: AppEnvironment?
    @State private var startupError: String?

    init() {
        do {
            let container = try PersistenceController.sharedContainer()
            _environment = State(initialValue: AppEnvironment(container: container))
        } catch {
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootView()
                    .environment(environment)
                    .environment(environment.router)
                    .modelContainer(environment.container)
            } else {
                StartupErrorView(message: startupError ?? "Erro desconhecido.")
            }
        }
    }
}

/// Exibido se o banco local não puder ser aberto. Não apaga dados automaticamente.
struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: DayliSpacing.md) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DayliColor.rose)
            Text("Algo não saiu como esperado")
                .font(DayliFont.headlineMedium)
            Text("\(message) Seus dados não foram apagados. Feche o app e abra novamente; se persistir, reinicie o iPhone ou atualize o Dayli.")
                .font(DayliFont.bodyMedium)
                .foregroundStyle(DayliColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DayliSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dayliScreenBackground()
    }
}
