import SwiftUI
import DayliCore

/// Onboarding em 4 etapas: boas-vindas, áreas da vida, rotina, permissões.
/// Sem cadastro obrigatório; tudo pode ser pulado e alterado depois no Perfil.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var step = 0
    @State private var name = ""
    @State private var areas: Set<LifeArea> = Set(LifeArea.allCases)
    @State private var routine = RoutineSettings.default
    @State private var notificationsGranted: Bool?
    @State private var calendarGranted: Bool?

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $step) {
                welcome.tag(0)
                areasStep.tag(1)
                routineStep.tag(2)
                permissionsStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)
            footer
        }
        .dayliScreenBackground()
    }

    // MARK: Cabeçalho e rodapé

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index <= step ? DayliColor.primary : DayliColor.divider)
                        .frame(width: index == step ? 24 : 8, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Etapa \(step + 1) de 4")
            Spacer()
            if step < 3 {
                Button("Pular") { finish() }
                    .font(DayliFont.label)
                    .foregroundStyle(DayliColor.textSecondary)
                    .accessibilityHint("Conclui a configuração com as opções padrão")
            }
        }
        .padding(.horizontal, DayliSpacing.screenMargin)
        .padding(.vertical, DayliSpacing.md)
    }

    private var footer: some View {
        HStack(spacing: DayliSpacing.sm) {
            if step > 0 {
                Button("Voltar") { step -= 1 }
                    .buttonStyle(.dayliSecondary)
                    .frame(maxWidth: 120)
            }
            Button(step == 3 ? "Começar" : "Continuar") {
                Haptics.light()
                if step == 3 { finish() } else { step += 1 }
            }
            .buttonStyle(.dayliPrimary)
            .accessibilityIdentifier("onboarding.next")
        }
        .padding(.horizontal, DayliSpacing.screenMargin)
        .padding(.bottom, DayliSpacing.md)
    }

    // MARK: Etapas

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DayliSpacing.lg) {
                Image(systemName: "sun.horizon")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(DayliColor.lavender)
                    .padding(.top, DayliSpacing.xl)
                    .accessibilityHidden(true)
                Text("Dayli")
                    .font(DayliFont.display)
                    .foregroundStyle(DayliColor.textPrimary)
                Text("Sua vida, no seu ritmo.")
                    .font(DayliFont.headlineMedium)
                    .foregroundStyle(DayliColor.textSecondary)
                Text("Organize trabalho, estudos, treinos, relações e descanso em um só lugar — com calma e sem cobranças.")
                    .font(DayliFont.bodyLarge)
                    .foregroundStyle(DayliColor.textPrimary)
                VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                    Text("Como podemos te chamar?")
                        .font(DayliFont.label)
                        .foregroundStyle(DayliColor.textSecondary)
                    TextField("Seu nome (opcional)", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .padding(14)
                        .background(DayliColor.surface, in: RoundedRectangle(cornerRadius: DayliRadius.input, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DayliRadius.input, style: .continuous).strokeBorder(DayliColor.border))
                        .accessibilityIdentifier("onboarding.name")
                }
                InlineNotice(style: .info, message: "Seus dados ficam no seu iPhone. Não é preciso criar conta.")
            }
            .padding(.horizontal, DayliSpacing.screenMargin)
        }
    }

    private var areasStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DayliSpacing.md) {
                Text("Quais áreas da sua vida você quer cuidar?")
                    .font(DayliFont.headlineLarge)
                    .foregroundStyle(DayliColor.textPrimary)
                Text("Você pode mudar isso quando quiser.")
                    .font(DayliFont.bodyMedium)
                    .foregroundStyle(DayliColor.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(LifeArea.allCases) { area in
                        let selected = areas.contains(area)
                        Button {
                            Haptics.selection()
                            if selected { areas.remove(area) } else { areas.insert(area) }
                        } label: {
                            HStack {
                                Image(systemName: area.symbolName)
                                    .frame(width: 32, height: 32)
                                    .background(DayliColor.lavender.opacity(0.18), in: Circle())
                                Text(area.title)
                                    .font(DayliFont.bodyMedium.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? DayliColor.primary : DayliColor.divider)
                            }
                            .foregroundStyle(DayliColor.textPrimary)
                            .padding(12)
                            .background(DayliColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(selected ? DayliColor.primary : DayliColor.border, lineWidth: selected ? 1.5 : 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, DayliSpacing.screenMargin)
            .padding(.top, DayliSpacing.md)
        }
    }

    private var routineStep: some View {
        Form {
            Section {
                timePicker("Acordo às", value: $routine.wake)
                timePicker("Durmo às", value: $routine.sleep)
            } header: {
                Text("Seu ritmo")
            } footer: {
                Text("Usamos esses horários para nunca sugerir atividades enquanto você descansa.")
            }
            Section("Trabalho") {
                timePicker("Início", value: $routine.workStart)
                timePicker("Fim", value: $routine.workEnd)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dias de trabalho").font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
                    WeekdayPicker(selection: $routine.workdays)
                }
                .padding(.vertical, 4)
            }
            Section("Preferências") {
                Picker("Melhor período para estudar", selection: $routine.studyPreference) {
                    ForEach(DayPeriodPreference.allCases) { Text($0.title).tag($0) }
                }
                Picker("Melhor período para treinar", selection: $routine.workoutPreference) {
                    ForEach(DayPeriodPreference.allCases) { Text($0.title).tag($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var permissionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DayliSpacing.md) {
                Text("Permissões, só se fizer sentido")
                    .font(DayliFont.headlineLarge)
                    .foregroundStyle(DayliColor.textPrimary)
                Text("Nada é obrigatório. Você pode ativar depois em Perfil.")
                    .font(DayliFont.bodyMedium)
                    .foregroundStyle(DayliColor.textSecondary)

                permissionCard(icon: "bell", title: "Notificações",
                               text: "Lembretes gentis de tarefas, compromissos e hábitos, além de um resumo pela manhã e uma revisão à noite.",
                               granted: notificationsGranted) {
                    Task {
                        let granted = await env.notifications.requestAuthorization()
                        notificationsGranted = granted
                        env.repository.settings().notificationsEnabled = granted
                        env.repository.commit()
                    }
                }
                permissionCard(icon: "calendar", title: "Calendário",
                               text: "Mostra seus eventos do Calendário junto com as tarefas e evita sugerir horários ocupados. Nada é alterado sem sua confirmação.",
                               granted: calendarGranted) {
                    Task {
                        let granted = await env.calendarService.requestFullAccess()
                        calendarGranted = granted
                        env.repository.settings().calendarIntegrationEnabled = granted
                        env.repository.commit()
                        env.applyCalendarSettings()
                    }
                }
                InlineNotice(style: .info, message: "Lembretes do app Lembretes ainda não são importados nesta versão; por isso não pedimos esse acesso.")
            }
            .padding(.horizontal, DayliSpacing.screenMargin)
            .padding(.top, DayliSpacing.md)
        }
    }

    private func permissionCard(icon: String, title: String, text: String, granted: Bool?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: DayliSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 36, height: 36)
                    .background(DayliColor.sage.opacity(0.2), in: Circle())
                    .accessibilityHidden(true)
                Text(title).font(DayliFont.headlineSmall)
                Spacer()
                if let granted {
                    Text(granted ? "Ativado" : "Não autorizado")
                        .font(DayliFont.caption)
                        .foregroundStyle(granted ? DayliColor.sageInk : DayliColor.textSecondary)
                }
            }
            Text(text).font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
            if granted == nil {
                Button("Permitir", action: action)
                    .buttonStyle(.dayliSecondary)
            } else if granted == false {
                Text("Tudo bem! Você pode mudar isso depois nos Ajustes do iPhone.")
                    .font(DayliFont.bodySmall)
                    .foregroundStyle(DayliColor.textSecondary)
            }
        }
        .dayliCard()
    }

    private func timePicker(_ title: String, value: Binding<TimeOfDay>) -> some View {
        DatePicker(title, selection: Binding(
            get: { value.wrappedValue.date(on: .now, calendar: .dayli) },
            set: { value.wrappedValue = TimeOfDay.from($0, calendar: .dayli) }
        ), displayedComponents: .hourAndMinute)
    }

    private func finish() {
        Haptics.success()
        env.repository.completeOnboarding(name: name, areas: areas, routine: routine)
        env.applyCalendarSettings()
    }
}
