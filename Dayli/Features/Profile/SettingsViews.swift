import SwiftUI
import SwiftData
import UserNotifications
import DayliCore

// MARK: - Notificações

struct NotificationSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Query private var settingsList: [AppSettings]
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]

    var body: some View {
        Form {
            if let settings = settingsList.first {
                let status = env.notifications.authorizationStatus
                Section {
                    switch status {
                    case .notDetermined:
                        Button("Permitir notificações") {
                            Task {
                                let granted = await env.notifications.requestAuthorization()
                                settings.notificationsEnabled = granted
                                env.repository.commit()
                            }
                        }
                    case .denied:
                        Text("As notificações estão desativadas nos Ajustes do iPhone.")
                            .foregroundStyle(DayliColor.textSecondary)
                        Button("Abrir Ajustes") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    default:
                        Toggle("Notificações do Dayli", isOn: bind(settings, \.notificationsEnabled))
                    }
                } footer: {
                    Text("O iOS pode atrasar ou agrupar notificações (Foco, Modo Pouca Energia, Resumo Programado). O Dayli não garante horário exato de entrega.")
                }

                if settings.notificationsEnabled && env.notifications.isAuthorized {
                    Section("Tipos") {
                        Toggle("Lembretes de tarefas", isOn: bind(settings, \.taskRemindersEnabled))
                        Toggle("Avisos de prazo (véspera)", isOn: bind(settings, \.deadlineAlertsEnabled))
                        Toggle("Alertas de compromissos", isOn: bind(settings, \.eventAlertsEnabled))
                        Toggle("Lembretes de hábitos", isOn: bind(settings, \.habitRemindersEnabled))
                    }
                    Section("Resumos") {
                        Toggle("Resumo matinal", isOn: bind(settings, \.morningSummaryEnabled))
                        if settings.morningSummaryEnabled {
                            TimeOfDayPicker(title: "Horário", value: minutesBinding(settings, \.morningSummaryMinutes))
                        }
                        Toggle("Revisão noturna", isOn: bind(settings, \.eveningReviewEnabled))
                        if settings.eveningReviewEnabled {
                            TimeOfDayPicker(title: "Horário", value: minutesBinding(settings, \.eveningReviewMinutes))
                        }
                    }
                    Section("Antecedência padrão") {
                        Picker("Compromissos", selection: bind(settings, \.defaultEventAlertOffset)) {
                            ForEach([0, 5, 10, 15, 30, 60], id: \.self) { Text($0 == 0 ? "Na hora" : "\($0) min antes").tag($0) }
                        }
                    }
                    Section {
                        Toggle("Horário de silêncio", isOn: bind(settings, \.quietHoursEnabled))
                        if settings.quietHoursEnabled {
                            TimeOfDayPicker(title: "Das", value: minutesBinding(settings, \.quietStartMinutes))
                            TimeOfDayPicker(title: "Até", value: minutesBinding(settings, \.quietEndMinutes))
                        }
                    } footer: {
                        Text("Lembretes que cairiam no silêncio são adiados para o fim dele.")
                    }
                    Section("Silenciar categorias") {
                        ForEach(categories) { category in
                            Toggle(category.name, isOn: Binding(
                                get: { !settings.mutedCategoryIDs.contains(category.id) },
                                set: { on in
                                    if on { settings.mutedCategoryIDs.removeAll { $0 == category.id } } else { settings.mutedCategoryIDs.append(category.id) }
                                    env.repository.commit()
                                }))
                        }
                    }
                    Section {
                        LabeledContent("Notificações agendadas", value: "\(env.notifications.lastScheduledCount)")
                    } footer: {
                        Text("Agendamos os próximos 7 dias, respeitando o limite de notificações do iOS. A lista é atualizada sempre que você abre o app ou muda algo.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Notificações")
        .task { await env.notifications.refreshAuthorization() }
    }

    private func bind<T>(_ settings: AppSettings, _ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0; env.repository.commit() })
    }

    private func minutesBinding(_ settings: AppSettings, _ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<TimeOfDay> {
        Binding(get: { TimeOfDay(minutesSinceMidnight: settings[keyPath: keyPath]) },
                set: { settings[keyPath: keyPath] = $0.minutesSinceMidnight; env.repository.commit() })
    }
}

// MARK: - Calendário

struct CalendarIntegrationView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Query private var settingsList: [AppSettings]

    var body: some View {
        let service = env.calendarService
        Form {
            if let settings = settingsList.first {
                Section {
                    LabeledContent("Status", value: service.accessState.description)
                    switch service.accessState {
                    case .notDetermined:
                        Button("Conectar Calendário Apple") {
                            Task {
                                let granted = await service.requestFullAccess()
                                settings.calendarIntegrationEnabled = granted
                                env.repository.commit()
                                env.applyCalendarSettings()
                            }
                        }
                    case .denied, .restricted, .writeOnly:
                        Text(service.accessState == .writeOnly
                             ? "Com acesso somente de escrita, o Dayli pode adicionar compromissos, mas não consegue mostrar seus eventos nem evitar conflitos."
                             : "O acesso foi negado ou revogado. O Dayli continua funcionando normalmente sem o Calendário.")
                            .font(DayliFont.bodySmall)
                            .foregroundStyle(DayliColor.textSecondary)
                        Button("Abrir Ajustes") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                    case .fullAccess:
                        Toggle("Mostrar eventos do Calendário", isOn: Binding(
                            get: { settings.calendarIntegrationEnabled },
                            set: { settings.calendarIntegrationEnabled = $0; env.repository.commit(); env.applyCalendarSettings() }))
                    }
                } footer: {
                    Text("Eventos do Calendário são lidos ao vivo e não são copiados para o Dayli. Eles nunca são alterados ou apagados sem sua confirmação.")
                }

                if service.accessState == .fullAccess && settings.calendarIntegrationEnabled {
                    Section("Calendários visíveis") {
                        ForEach(service.calendars()) { cal in
                            Toggle(isOn: Binding(
                                get: { settings.visibleCalendarIDs.isEmpty || settings.visibleCalendarIDs.contains(cal.id) },
                                set: { on in
                                    var ids = settings.visibleCalendarIDs.isEmpty ? service.calendars().map(\.id) : settings.visibleCalendarIDs
                                    if on { if !ids.contains(cal.id) { ids.append(cal.id) } } else { ids.removeAll { $0 == cal.id } }
                                    settings.visibleCalendarIDs = ids
                                    env.repository.commit()
                                    env.applyCalendarSettings()
                                })) {
                                HStack {
                                    Circle().fill(Color(hex: cal.colorHex)).frame(width: 10, height: 10)
                                    VStack(alignment: .leading) {
                                        Text(cal.title)
                                        Text(cal.sourceTitle).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    Section("Novos compromissos") {
                        Picker("Calendário padrão", selection: Binding(
                            get: { settings.defaultExportCalendarID ?? "" },
                            set: { settings.defaultExportCalendarID = $0.isEmpty ? nil : $0; env.repository.commit() })) {
                            Text("Perguntar / primeiro disponível").tag("")
                            ForEach(service.writableCalendars()) { Text($0.title).tag($0.id) }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Calendário Apple")
        .onAppear { service.refreshAuthorization() }
    }
}

// MARK: - Privacidade

struct PrivacySettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var settingsList: [AppSettings]

    var body: some View {
        Form {
            Section {
                Label("Seus dados ficam armazenados localmente neste iPhone, protegidos pela criptografia do sistema.", systemImage: "lock.iphone")
                Label("O Dayli não pede credenciais corporativas e não acessa sistemas bancários.", systemImage: "building.columns")
                Label("Evite registrar dados de clientes, contas ou informações confidenciais do trabalho.", systemImage: "hand.raised")
            }
            .font(DayliFont.bodySmall)
            if let settings = settingsList.first {
                Section {
                    Toggle("Ocultar detalhes nos widgets", isOn: Binding(
                        get: { settings.widgetHideDetails },
                        set: { settings.widgetHideDetails = $0; env.repository.commit() }))
                } footer: {
                    Text("Widgets podem aparecer na tela bloqueada. Com esta opção, mostram apenas \"Compromisso\" e \"Tarefa\" em vez dos títulos.")
                }
            }
            Section {
                NavigationLink("Inteligência artificial") { AISettingsView() }
                NavigationLink("Exportar ou excluir dados") { DataManagementView() }
            }
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Privacidade")
    }
}

// MARK: - IA

struct AISettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var settingsList: [AppSettings]
    @State private var urlText = ""
    @State private var urlError: String?
    @State private var confirmConsent = false

    var body: some View {
        Form {
            Section {
                Text("O assistente local funciona sem internet e sem enviar dados. A Dayli AI (servidor) é opcional e só é usada com seu consentimento.")
                    .font(DayliFont.bodySmall)
            }
            if let settings = settingsList.first {
                Section {
                    TextField("https://api.seudominio.com", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { saveURL(settings) }
                    Button("Salvar endereço") { saveURL(settings) }
                    if let urlError { InlineNotice(style: .error, message: urlError) }
                } header: {
                    Text("Servidor da Dayli AI")
                } footer: {
                    Text("O app nunca guarda chaves de provedores de IA. O servidor do Dayli autentica o aparelho e protege as credenciais. Deixe em branco para manter a IA remota desativada.")
                }

                Section {
                    Toggle("Usar Dayli AI (servidor)", isOn: Binding(
                        get: { settings.aiEnabled && settings.aiConsentDate != nil },
                        set: { on in
                            if on { confirmConsent = true } else {
                                settings.aiEnabled = false
                                settings.aiConsentDate = nil
                                env.repository.commit()
                            }
                        }))
                    .disabled(!env.isRemoteAIConfigured)
                    if let date = settings.aiConsentDate {
                        LabeledContent("Consentimento em", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    Toggle("Enviar títulos das tarefas", isOn: Binding(
                        get: { settings.aiShareTitles },
                        set: { settings.aiShareTitles = $0; env.repository.commit() }))
                        .disabled(!settings.hasAIConsent)
                } header: {
                    Text("Consentimento")
                } footer: {
                    Text("Sem enviar títulos, a IA recebe apenas rótulos como \"Tarefa de Trabalho\", horários, prioridades e durações. Em qualquer caso, e-mails, CPF, CNPJ, números de conta, cartão e telefone são removidos antes do envio.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Inteligência artificial")
        .onAppear { urlText = settingsList.first?.aiBackendURL ?? "" }
        .alert("Autorizar envio à Dayli AI?", isPresented: $confirmConsent) {
            Button("Autorizar") {
                if let settings = settingsList.first {
                    settings.aiEnabled = true
                    settings.aiConsentDate = .now
                    env.repository.commit()
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Quando você usar o modo Dayli AI, seu pedido e um contexto mínimo (horários ocupados, tarefas pendentes, rotina) serão enviados ao servidor configurado. Você pode revogar a qualquer momento.")
        }
    }

    private func saveURL(_ settings: AppSettings) {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            settings.aiBackendURL = ""
            settings.aiEnabled = false
            urlError = nil
            env.repository.commit()
            return
        }
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host != nil else {
            urlError = AIServiceError.insecureURL.localizedDescription
            return
        }
        urlError = nil
        settings.aiBackendURL = url.absoluteString
        env.repository.commit()
    }
}

// MARK: - Dados

struct DataManagementView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var confirmDeleteAll = false
    @State private var confirmDemo = false
    @State private var hasDemo = false

    var body: some View {
        Form {
            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Compartilhar arquivo exportado", systemImage: "square.and.arrow.up") }
                } else {
                    Button("Gerar exportação (JSON)") {
                        do { exportURL = try DataExporter.makeFile(repository: env.repository) } catch { exportError = "Não foi possível gerar o arquivo." }
                    }
                }
                if let exportError { InlineNotice(style: .error, message: exportError) }
            } header: {
                Text("Exportar")
            } footer: {
                Text("Inclui perfil, rotina, categorias, tarefas, compromissos, hábitos e metas. Eventos do Calendário Apple não são incluídos.")
            }

            Section {
                if hasDemo {
                    Button("Remover dados de demonstração") {
                        DemoDataSeeder.remove(from: env.repository)
                        hasDemo = false
                    }
                } else {
                    Button("Carregar dados de demonstração") { confirmDemo = true }
                }
            } header: {
                Text("Modo demonstração")
            } footer: {
                Text("Itens de exemplo marcados com [Demo], úteis para conhecer o app. Podem ser removidos a qualquer momento sem afetar seus dados.")
            }

            Section {
                Button("Excluir todos os meus dados", role: .destructive) { confirmDeleteAll = true }
            } footer: {
                Text("Remove permanentemente tudo o que o Dayli guardou neste iPhone. Eventos do Calendário Apple não são afetados.")
            }
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Seus dados")
        .onAppear { hasDemo = DemoDataSeeder.hasDemoData(in: env.repository.context) }
        .confirmationDialog("Carregar dados de demonstração?", isPresented: $confirmDemo, titleVisibility: .visible) {
            Button("Carregar") {
                DemoDataSeeder.load(into: env.repository)
                hasDemo = true
            }
        }
        .confirmationDialog("Excluir todos os dados?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Excluir tudo", role: .destructive) {
                do {
                    try env.repository.deleteAllData()
                    WidgetSnapshotWriter.clear()
                    Task { await env.notifications.rebuild(using: env.repository, external: { _ in [] }) }
                } catch {
                    exportError = "Não foi possível excluir os dados. Tente novamente."
                }
            }
        } message: {
            Text("Essa ação não pode ser desfeita. Você voltará para a tela de boas-vindas.")
        }
    }
}

// MARK: - Sobre

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dayli").font(DayliFont.headlineLarge)
                    Text("Sua vida, no seu ritmo.").foregroundStyle(DayliColor.textSecondary)
                }
                LabeledContent("Versão", value: AppConfig.appVersion)
            }
            Section("Princípios") {
                Text("• Seus dados são seus: armazenamento local, exportação e exclusão a qualquer momento.")
                Text("• Nenhuma alteração por IA sem a sua confirmação.")
                Text("• Organização sem culpa: sem mensagens negativas, com espaço para descanso.")
                Text("• O Dayli não oferece orientação médica, financeira ou jurídica.")
            }
            .font(DayliFont.bodySmall)
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Sobre")
    }
}
