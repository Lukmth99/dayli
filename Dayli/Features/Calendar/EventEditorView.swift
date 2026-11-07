import SwiftUI
import SwiftData
import DayliCore

/// Criação e edição de compromissos do Dayli, com detecção de conflitos e
/// espelhamento opcional no Calendário Apple.
struct EventEditorView: View {
    let event: CalendarEvent?
    var initialStart: Date = .now

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]

    @State private var draft = EventDraft()
    @State private var mirror = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var loaded = false

    init(event: CalendarEvent?, initialStart: Date = .now) {
        self.event = event
        self.initialStart = initialStart
    }

    private var conflicts: [BusyInterval] {
        guard !draft.isAllDay, draft.end > draft.start else { return [] }
        let window = DateInterval(start: Calendar.dayli.startOfDay(for: draft.start), end: Calendar.dayli.endOfDay(for: draft.end))
        return env.repository.conflicts(start: draft.start, end: draft.end, excluding: event?.id,
                                        external: env.calendarService.events(in: window))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título do compromisso", text: $draft.title)
                        .font(DayliFont.bodyLarge)
                        .accessibilityIdentifier("event.title")
                    TextField("Local", text: $draft.location)
                        .textContentType(.location)
                }

                Section {
                    Toggle("Dia todo", isOn: $draft.isAllDay.animation())
                    DatePicker("Início", selection: Binding(
                        get: { draft.start },
                        set: { newStart in
                            // Mantém a duração ao mover o início.
                            let duration = max(900, draft.end.timeIntervalSince(draft.start))
                            draft.start = newStart
                            draft.end = newStart.addingTimeInterval(duration)
                        }), displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Término", selection: $draft.end, in: draft.start..., displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                    if !conflicts.isEmpty {
                        InlineNotice(style: .warning,
                                     message: "Conflita com: " + conflicts.prefix(3).map(\.title).joined(separator: ", ") + ". Você pode salvar mesmo assim.")
                    }
                } header: {
                    Text("Horário")
                }

                Section("Detalhes") {
                    CategoryPicker(categories: categories, selection: $draft.categoryID)
                    Picker("Alerta", selection: $draft.alertOffsetMinutes) {
                        Text("Sem alerta").tag(Int?.none)
                        Text("Na hora").tag(Int?.some(0))
                        Text("5 min antes").tag(Int?.some(5))
                        Text("15 min antes").tag(Int?.some(15))
                        Text("30 min antes").tag(Int?.some(30))
                        Text("1 hora antes").tag(Int?.some(60))
                        Text("1 dia antes").tag(Int?.some(1_440))
                    }
                    RecurrencePicker(rule: $draft.recurrence, anchor: draft.start)
                    TextField("Descrição", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                calendarSection

                if let errorMessage {
                    Section { InlineNotice(style: .error, message: errorMessage) }
                }

                if event != nil {
                    Section {
                        Button("Excluir compromisso", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .dayliScreenBackground()
            .navigationTitle(event == nil ? "Novo compromisso" : "Editar compromisso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("event.save")
                }
            }
            .confirmationDialog("Excluir este compromisso?", isPresented: $confirmDelete, titleVisibility: .visible) {
                if let event, event.externalEventIdentifier != nil {
                    Button("Excluir do Dayli e do Calendário Apple", role: .destructive) { delete(alsoExternal: true) }
                    Button("Excluir só do Dayli", role: .destructive) { delete(alsoExternal: false) }
                } else {
                    Button("Excluir", role: .destructive) { delete(alsoExternal: false) }
                }
            } message: {
                Text(event?.recurrence != nil ? "Todas as ocorrências deste compromisso serão excluídas." : "Essa ação não pode ser desfeita.")
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private var calendarSection: some View {
        let state = env.calendarService.accessState
        Section {
            if state.canWrite {
                Toggle("Adicionar ao Calendário Apple", isOn: $mirror)
                if mirror && state.canRead {
                    Picker("Calendário", selection: Binding(
                        get: { draft.mirrorToCalendarID ?? env.repository.settings().defaultExportCalendarID ?? env.calendarService.writableCalendars().first?.id ?? "" },
                        set: { draft.mirrorToCalendarID = $0 })) {
                        ForEach(env.calendarService.writableCalendars()) { cal in
                            Text(cal.title).tag(cal.id)
                        }
                    }
                }
            } else if state == .notDetermined {
                Button("Conectar ao Calendário Apple") {
                    Task {
                        if await env.calendarService.requestFullAccess() {
                            env.repository.settings().calendarIntegrationEnabled = true
                            env.repository.commit()
                            env.applyCalendarSettings()
                        }
                    }
                }
            } else {
                Text("Sem acesso ao Calendário. Você pode permitir em Ajustes › Dayli › Calendários.")
                    .font(DayliFont.bodySmall)
                    .foregroundStyle(DayliColor.textSecondary)
            }
        } header: {
            Text("Calendário Apple")
        } footer: {
            Text("O compromisso continua salvo no Dayli mesmo sem o Calendário.")
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let event {
            draft = EventDraft(event: event)
            mirror = event.externalEventIdentifier != nil
        } else {
            draft = EventDraft(start: initialStart)
            draft.start = initialStart
            draft.end = initialStart.addingTimeInterval(3_600)
            draft.alertOffsetMinutes = env.repository.settings().defaultEventAlertOffset
        }
    }

    private func save() {
        do {
            let saved: CalendarEvent
            if let event {
                try env.repository.updateEvent(event, from: draft)
                saved = event
            } else {
                saved = try env.repository.createEvent(from: draft)
            }
            syncMirror(saved)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }

    /// Espelha no Calendário Apple quando solicitado. Falhas não impedem o salvamento no Dayli.
    private func syncMirror(_ saved: CalendarEvent) {
        let service = env.calendarService
        if mirror, service.accessState.canWrite {
            let calendarID = draft.mirrorToCalendarID ?? env.repository.settings().defaultExportCalendarID ?? service.writableCalendars().first?.id ?? ""
            do {
                let identifier = try service.upsertMirror(of: saved, calendarID: calendarID)
                env.repository.linkExternal(saved, eventIdentifier: identifier, calendarIdentifier: calendarID)
            } catch {
                AppLog.calendar.error("Falha ao espelhar compromisso no Calendário")
            }
        } else if !mirror, saved.externalEventIdentifier != nil {
            // Desligar o espelhamento apenas desvincula; não apaga o evento externo sem confirmação explícita.
            env.repository.linkExternal(saved, eventIdentifier: nil, calendarIdentifier: nil)
        }
    }

    private func delete(alsoExternal: Bool) {
        guard let event else { return }
        if alsoExternal, let identifier = event.externalEventIdentifier {
            do {
                try env.calendarService.deleteExternalEvent(identifier: identifier)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        env.repository.delete(event)
        dismiss()
    }
}
