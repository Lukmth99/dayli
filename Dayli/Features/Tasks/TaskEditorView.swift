import SwiftUI
import SwiftData
import DayliCore

/// Criação e edição completa de tarefas.
struct TaskEditorView: View {
    let task: TaskItem?
    var initialDraft: TaskDraft? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]

    @State private var draft = TaskDraft()
    @State private var newSubtask = ""
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var loaded = false

    init(task: TaskItem?, initialDraft: TaskDraft? = nil) {
        self.task = task
        self.initialDraft = initialDraft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("O que você quer fazer?", text: $draft.title, axis: .vertical)
                        .font(DayliFont.bodyLarge)
                        .accessibilityIdentifier("task.title")
                    TextField("Descrição e observações", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Organização") {
                    CategoryPicker(categories: categories, selection: $draft.categoryID)
                    Picker("Prioridade", selection: $draft.priority) {
                        ForEach(Priority.allCases.reversed()) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Duração estimada: \(DayliFormat.duration(minutes: draft.estimatedMinutes))",
                            value: $draft.estimatedMinutes, in: 5...480, step: 5)
                }

                Section {
                    Toggle("Definir data", isOn: $draft.hasDate.animation())
                    if draft.hasDate {
                        Toggle("Horário específico", isOn: $draft.hasTime.animation())
                        DatePicker("Quando", selection: $draft.dueDate,
                                   displayedComponents: draft.hasTime ? [.date, .hourAndMinute] : [.date])
                        Picker("Lembrete", selection: $draft.reminderOffsetMinutes) {
                            Text("Sem lembrete").tag(Int?.none)
                            Text(draft.hasTime ? "Na hora" : "Às 9h do dia").tag(Int?.some(0))
                            if draft.hasTime {
                                Text("15 min antes").tag(Int?.some(15))
                                Text("30 min antes").tag(Int?.some(30))
                                Text("1 hora antes").tag(Int?.some(60))
                            }
                            Text("1 dia antes").tag(Int?.some(1_440))
                        }
                        RecurrencePicker(rule: $draft.recurrence, anchor: draft.dueDate)
                    }
                } header: {
                    Text("Tempo")
                } footer: {
                    if draft.recurrence != nil {
                        Text("Ao concluir, apenas esta ocorrência é concluída e a próxima é criada automaticamente.")
                    }
                }

                Section("Subtarefas") {
                    ForEach($draft.subtasks) { $sub in
                        HStack {
                            Button { sub.isDone.toggle() } label: {
                                Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(sub.isDone ? DayliColor.sage : DayliColor.divider)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sub.isDone ? "Feita" : "Pendente")
                            TextField("Subtarefa", text: $sub.title)
                        }
                    }
                    .onDelete { draft.subtasks.remove(atOffsets: $0) }
                    .onMove { draft.subtasks.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("Adicionar passo", text: $newSubtask)
                            .onSubmit(addSubtask)
                        Button("Adicionar", action: addSubtask)
                            .disabled(newSubtask.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let errorMessage {
                    Section { InlineNotice(style: .error, message: errorMessage) }
                }

                if let task {
                    Section {
                        Button(task.isCompleted ? "Reabrir tarefa" : "Concluir tarefa") {
                            env.repository.toggleCompletion(task)
                            dismiss()
                        }
                        Button("Duplicar") {
                            env.repository.duplicate(task)
                            dismiss()
                        }
                        Button("Excluir tarefa", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .dayliScreenBackground()
            .navigationTitle(task == nil ? "Nova tarefa" : "Editar tarefa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("task.save")
                }
            }
            .confirmationDialog("Excluir esta tarefa?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    if let task { env.repository.delete(task) }
                    dismiss()
                }
            } message: {
                Text("Essa ação não pode ser desfeita.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let task {
            draft = TaskDraft(task: task)
        } else if let initialDraft {
            draft = initialDraft
        }
    }

    private func addSubtask() {
        guard let title = InputValidator.sanitizedTitle(newSubtask) else { return }
        draft.subtasks.append(.init(title: title))
        newSubtask = ""
    }

    private func save() {
        do {
            if let task {
                try env.repository.updateTask(task, from: draft)
            } else {
                try env.repository.createTask(from: draft)
            }
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.warning()
        }
    }
}

/// Seletor de recorrência compartilhado por tarefas e compromissos.
struct RecurrencePicker: View {
    @Binding var rule: RecurrenceRule?
    let anchor: Date

    private var frequencyBinding: Binding<RecurrenceRule.Frequency?> {
        Binding(
            get: { rule?.frequency },
            set: { newValue in
                if let newValue {
                    let weekday = Calendar.dayli.component(.weekday, from: anchor)
                    rule = RecurrenceRule(frequency: newValue, interval: rule?.interval ?? 1,
                                          weekdays: newValue == .weekly ? (rule?.weekdays.isEmpty == false ? rule!.weekdays : [weekday]) : [],
                                          endDate: rule?.endDate)
                } else {
                    rule = nil
                }
            })
    }

    var body: some View {
        Picker("Repetir", selection: frequencyBinding) {
            Text("Nunca").tag(RecurrenceRule.Frequency?.none)
            ForEach(RecurrenceRule.Frequency.allCases) { Text($0.title).tag(RecurrenceRule.Frequency?.some($0)) }
        }
        if let current = rule {
            Stepper("A cada \(current.interval) \(unit(current))", value: Binding(
                get: { current.interval },
                set: { rule?.interval = max(1, $0) }), in: 1...30)
            if current.frequency == .weekly {
                WeekdayPicker(selection: Binding(
                    get: { current.weekdays },
                    set: { rule?.weekdays = $0 }))
                    .padding(.vertical, 4)
            }
            Toggle("Terminar em uma data", isOn: Binding(
                get: { current.endDate != nil },
                set: { rule?.endDate = $0 ? Calendar.dayli.date(byAdding: .month, value: 3, to: anchor) : nil }))
            if let end = current.endDate {
                DatePicker("Até", selection: Binding(get: { end }, set: { rule?.endDate = $0 }), in: anchor..., displayedComponents: .date)
            }
        }
    }

    private func unit(_ rule: RecurrenceRule) -> String {
        let plural = rule.interval > 1
        switch rule.frequency {
        case .daily: return plural ? "dias" : "dia"
        case .weekly: return plural ? "semanas" : "semana"
        case .monthly: return plural ? "meses" : "mês"
        case .yearly: return plural ? "anos" : "ano"
        }
    }
}
