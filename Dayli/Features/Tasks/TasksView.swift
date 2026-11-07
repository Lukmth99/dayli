import SwiftUI
import SwiftData
import DayliCore

struct TasksView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var allTasks: [TaskItem]
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]

    @State private var filter: TaskFilter = .today
    @State private var search = ""
    @State private var sort: TaskSort = .dueDate
    @State private var categoryFilter: UUID?
    @State private var priorityFilter: Priority?
    @State private var editingTask: TaskItem?
    @State private var reschedulingTask: TaskItem?
    @State private var pendingDeletion: TaskItem?
    @State private var quickTitle = ""
    @FocusState private var quickFieldFocused: Bool

    private var calendar: Calendar { .dayli }

    private var visibleTasks: [TaskItem] {
        let now = Date.now
        let term = search.trimmingCharacters(in: .whitespaces)
        let base = allTasks.filter { task in
            if !term.isEmpty {
                // A busca percorre todas as tarefas, independentemente do filtro.
                return task.title.localizedCaseInsensitiveContains(term) || task.notes.localizedCaseInsensitiveContains(term)
                    || (task.category?.name.localizedCaseInsensitiveContains(term) ?? false)
            }
            return filter.matches(dueDate: task.dueDate, isCompleted: task.isCompleted, now: now, calendar: calendar)
        }
        .filter { categoryFilter == nil || $0.category?.id == categoryFilter }
        .filter { priorityFilter == nil || $0.priority == priorityFilter }

        switch sort {
        case .dueDate:
            return base.sorted { ($0.dueDate ?? .distantFuture, -$0.priorityRaw) < ($1.dueDate ?? .distantFuture, -$1.priorityRaw) }
        case .priority:
            return base.sorted { ($0.priorityRaw, $1.dueDate ?? .distantFuture) > ($1.priorityRaw, $0.dueDate ?? .distantFuture) }
        case .title:
            return base.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .created:
            return base.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func count(_ f: TaskFilter) -> Int {
        let now = Date.now
        return allTasks.filter { f.matches(dueDate: $0.dueDate, isCompleted: $0.isCompleted, now: now, calendar: calendar) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterChips
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    if filter == .today && search.isEmpty {
                        todaySummary
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    }
                }

                let tasks = visibleTasks
                if tasks.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(tasks) { task in
                            TaskRow(task: task,
                                    onToggle: { withAnimation { env.repository.toggleCompletion(task) } },
                                    onOpen: { editingTask = task },
                                    onToggleSubtask: { env.repository.toggleSubtask($0) })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { pendingDeletion = task } label: { Label("Excluir", systemImage: "trash") }
                                    if !task.isCompleted {
                                        Button { reschedulingTask = task } label: { Label("Reagendar", systemImage: "calendar") }
                                            .tint(DayliColor.lavender)
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if !task.isCompleted {
                                        Button { env.repository.rescheduleToTomorrow(task) } label: { Label("Amanhã", systemImage: "arrow.right") }
                                            .tint(DayliColor.softBlue)
                                    }
                                    Button { env.repository.duplicate(task) } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
                                        .tint(DayliColor.sage)
                                }
                                .contextMenu { contextMenu(for: task) }
                        }
                    } header: {
                        Text(search.isEmpty ? filter.title : "Resultados")
                            .font(DayliFont.headlineMedium)
                            .foregroundStyle(DayliColor.textPrimary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dayliScreenBackground()
            .navigationTitle("Tarefas")
            .searchable(text: $search, prompt: "Buscar tarefas ou categorias")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) { QuickAddToolbarButton() }
            }
            .safeAreaInset(edge: .bottom) { quickAddBar }
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
            .sheet(item: $reschedulingTask) { RescheduleSheet(task: $0) }
            .confirmationDialog("Excluir esta tarefa?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                                titleVisibility: .visible, presenting: pendingDeletion) { task in
                Button("Excluir", role: .destructive) {
                    withAnimation { env.repository.delete(task) }
                    pendingDeletion = nil
                }
                Button("Cancelar", role: .cancel) { pendingDeletion = nil }
            } message: { task in
                Text(task.recurrence != nil ? "Somente esta ocorrência será excluída; as próximas não serão geradas." : "Essa ação não pode ser desfeita.")
            }
        }
    }

    // MARK: Componentes

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskFilter.allCases) { f in
                    let selected = f == filter
                    Button {
                        Haptics.selection()
                        filter = f
                    } label: {
                        HStack(spacing: 6) {
                            Text(f.title)
                            if f != .completed {
                                Text("\(count(f))")
                                    .font(DayliFont.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((selected ? Color.white : DayliColor.textSecondary).opacity(0.2), in: Capsule())
                            }
                        }
                        .font(DayliFont.label)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(selected ? DayliColor.onPrimary : DayliColor.textPrimary)
                        .background(selected ? DayliColor.primary : DayliColor.surfaceMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, DayliSpacing.screenMargin)
            .padding(.vertical, DayliSpacing.sm)
        }
    }

    private var todaySummary: some View {
        let now = Date.now
        let today = allTasks.filter { task in
            guard let due = task.dueDate else { return false }
            if task.isCompleted { return calendar.isDate(task.completedAt ?? due, inSameDayAs: now) || calendar.isDate(due, inSameDayAs: now) }
            return calendar.daysBetween(now, due) <= 0
        }
        let progress = DailyProgress(total: today.count, completed: today.filter(\.isCompleted).count)
        return HStack(spacing: 12) {
            ProgressRing(value: progress.fraction).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(progress.completed) de \(progress.total) concluídas").font(DayliFont.headlineSmall)
                Text("Ritmo suave, sem pressa").font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(DayliColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        Group {
            if !search.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "Nada encontrado", message: "Tente outra palavra ou limpe os filtros.")
            } else {
                switch filter {
                case .completed:
                    EmptyStateView(systemImage: "checkmark.seal", title: "Nada concluído ainda", message: "Quando você concluir algo, aparece aqui. Cada passo conta.")
                case .today:
                    EmptyStateView(systemImage: "sun.max", title: "Nada pendente para hoje", message: "Aproveite para respirar — ou adicione algo abaixo.")
                default:
                    EmptyStateView(systemImage: "tray", title: "Lista vazia", message: "Nenhuma tarefa por aqui.")
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Ordenar por", selection: $sort) {
                ForEach(TaskSort.allCases) { Text($0.title).tag($0) }
            }
            Picker("Prioridade", selection: $priorityFilter) {
                Text("Todas as prioridades").tag(Priority?.none)
                ForEach(Priority.allCases.reversed()) { Text($0.title).tag(Priority?.some($0)) }
            }
            Picker("Categoria", selection: $categoryFilter) {
                Text("Todas as categorias").tag(UUID?.none)
                ForEach(categories) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            if categoryFilter != nil || priorityFilter != nil {
                Button("Limpar filtros") { categoryFilter = nil; priorityFilter = nil }
            }
        } label: {
            Image(systemName: categoryFilter != nil || priorityFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filtrar e ordenar")
    }

    @ViewBuilder
    private func contextMenu(for task: TaskItem) -> some View {
        Button { env.repository.toggleCompletion(task) } label: {
            Label(task.isCompleted ? "Reabrir" : "Concluir", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
        }
        Button { editingTask = task } label: { Label("Editar", systemImage: "pencil") }
        Button { env.repository.duplicate(task) } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
        if !task.isCompleted {
            Button { reschedulingTask = task } label: { Label("Reagendar", systemImage: "calendar") }
        }
        Menu("Mover para categoria") {
            Button("Sem categoria") { env.repository.move(task, to: nil) }
            ForEach(categories) { category in
                Button(category.name) { env.repository.move(task, to: category) }
            }
        }
        Button(role: .destructive) { pendingDeletion = task } label: { Label("Excluir", systemImage: "trash") }
    }

    private var quickAddBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundStyle(DayliColor.textSecondary).accessibilityHidden(true)
            TextField("Adicionar nova tarefa…", text: $quickTitle)
                .focused($quickFieldFocused)
                .submitLabel(.done)
                .onSubmit(saveQuickTask)
                .accessibilityIdentifier("tasks.quickAdd")
            if !quickTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Salvar", action: saveQuickTask)
                    .font(DayliFont.label)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(DayliColor.onPrimary)
                    .background(DayliColor.primary, in: Capsule())
                    .accessibilityIdentifier("tasks.quickAdd.save")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DayliColor.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(DayliColor.border, lineWidth: 0.5))
        .padding(.horizontal, DayliSpacing.screenMargin)
        .padding(.bottom, 8)
    }

    private func saveQuickTask() {
        // Tarefas criadas no filtro "Hoje" já nascem para hoje; nos demais, sem data.
        let due: Date? = (filter == .today) ? calendar.startOfDay(for: .now) : nil
        guard (try? env.repository.quickAddTask(title: quickTitle, dueDate: due)) != nil else { return }
        Haptics.success()
        quickTitle = ""
    }
}

/// Folha de reagendamento rápido.
struct RescheduleSheet: View {
    let task: TaskItem
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var hasTime = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Hoje") { apply(Calendar.dayli.startOfDay(for: .now), time: false) }
                    Button("Amanhã") { env.repository.rescheduleToTomorrow(task); dismiss() }
                    Button("Próxima segunda-feira") {
                        let next = Calendar.dayli.nextDate(after: .now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? .now
                        apply(next, time: false)
                    }
                }
                Section("Escolher data") {
                    Toggle("Definir horário", isOn: $hasTime)
                    DatePicker("Data", selection: $date, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                        .datePickerStyle(.graphical)
                    Button("Reagendar") { apply(date, time: hasTime) }
                        .buttonStyle(.dayliPrimary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Reagendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .onAppear {
                date = task.dueDate ?? .now
                hasTime = task.hasTime
            }
        }
    }

    private func apply(_ date: Date, time: Bool) {
        env.repository.reschedule(task, to: date, hasTime: time)
        Haptics.success()
        dismiss()
    }
}
