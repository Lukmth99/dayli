import SwiftUI
import SwiftData
import DayliCore

struct GoalsView: View {
    @Query(sort: \Goal.endDate) private var goals: [Goal]
    @State private var creating = false
    @State private var showFinished = false

    private var visible: [Goal] {
        goals.filter { showFinished ? true : ($0.status == .active || $0.status == .paused) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DayliSpacing.md) {
                Toggle("Mostrar concluídas e arquivadas", isOn: $showFinished)
                    .font(DayliFont.bodySmall)
                if visible.isEmpty {
                    EmptyStateView(systemImage: "flag", title: "Nenhuma meta por aqui",
                                   message: "Que tal algo como \"Ler dois livros\" ou \"Treinar 12 vezes no mês\"?",
                                   actionTitle: "Criar meta") { creating = true }
                        .dayliCard()
                }
                ForEach(visible) { goal in
                    NavigationLink(value: MyLifeRoute.goal(goal.id)) { GoalCard(goal: goal) }
                        .buttonStyle(.plain)
                }
            }
            .padding(DayliSpacing.screenMargin)
        }
        .dayliScreenBackground()
        .navigationTitle("Metas")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nova meta")
            }
        }
        .sheet(isPresented: $creating) { GoalEditorView(goal: nil) }
    }
}

struct GoalCard: View {
    let goal: Goal

    var body: some View {
        let progress = goal.progress(calendar: .dayli)
        HStack(spacing: DayliSpacing.md) {
            ProgressRing(value: progress, tint: Color(hex: goal.category?.colorHex ?? "#B8A3CE"))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let category = goal.category { CategoryChip(category: category) }
                    if goal.status != .active { InfoPill(text: goal.status.title) }
                }
                Text(goal.title).font(DayliFont.headlineSmall).foregroundStyle(DayliColor.textPrimary)
                Text(detail).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
            }
            Spacer()
        }
        .dayliCard()
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let deadline = "Até \(DayliFormat.dayMonth(goal.endDate))"
        switch goal.progressKind {
        case .manual:
            return "\(format(goal.currentValue)) de \(format(goal.targetValue ?? 0)) \(goal.unit) · \(deadline)"
        case .milestones:
            return "\(goal.milestones.filter(\.isDone).count) de \(goal.milestones.count) etapas · \(deadline)"
        case .linkedHabit:
            return "\(goal.linkedCount(calendar: .dayli)) de \(format(goal.targetValue ?? 0)) registros · \(deadline)"
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt_BR")))
    }
}

struct GoalDetailView: View {
    let goal: Goal
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var manualValue: Double = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DayliSpacing.lg) {
                GoalCard(goal: goal)
                if !goal.details.isEmpty {
                    Text(goal.details).font(DayliFont.bodyMedium).foregroundStyle(DayliColor.textSecondary)
                }
                switch goal.progressKind {
                case .manual:
                    VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                        SectionHeader(title: "Atualizar progresso")
                        Stepper(value: $manualValue, in: 0...max(goal.targetValue ?? 100, manualValue), step: 1) {
                            Text("Valor atual: \(manualValue.formatted(.number.precision(.fractionLength(0...1)))) \(goal.unit)")
                        }
                        Button("Salvar progresso") {
                            env.repository.updateProgress(goal, currentValue: manualValue)
                            Haptics.success()
                        }
                        .buttonStyle(.dayliPrimary)
                    }
                    .dayliCard()
                case .milestones:
                    VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                        SectionHeader(title: "Etapas")
                        if goal.milestones.isEmpty {
                            Text("Adicione etapas editando a meta.").font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
                        }
                        ForEach(goal.sortedMilestones) { milestone in
                            HStack {
                                CompletionCircle(isCompleted: milestone.isDone, colorHex: goal.category?.colorHex ?? "#B8A3CE") {
                                    env.repository.toggleMilestone(milestone)
                                }
                                Text(milestone.title)
                                    .strikethrough(milestone.isDone)
                                    .foregroundStyle(DayliColor.textPrimary)
                                Spacer()
                            }
                        }
                    }
                    .dayliCard()
                case .linkedHabit:
                    VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                        SectionHeader(title: "Vinculada a hábito")
                        if let habit = goal.linkedHabit {
                            Text("O progresso conta os dias em que \"\(habit.title)\" foi cumprido entre \(DayliFormat.dayMonth(goal.startDate)) e \(DayliFormat.dayMonth(goal.endDate)).")
                                .font(DayliFont.bodySmall)
                                .foregroundStyle(DayliColor.textSecondary)
                        } else {
                            InlineNotice(style: .warning, message: "O hábito vinculado foi excluído. Edite a meta para escolher outro.")
                        }
                    }
                    .dayliCard()
                }
                HStack {
                    if goal.status == .active {
                        Button("Pausar") { env.repository.setStatus(goal, .paused) }.buttonStyle(.dayliSecondary)
                    } else if goal.status == .paused || goal.status == .archived {
                        Button("Retomar") { env.repository.setStatus(goal, .active) }.buttonStyle(.dayliSecondary)
                    }
                    if goal.status != .archived {
                        Button("Arquivar") { env.repository.setStatus(goal, .archived) }.buttonStyle(.dayliSecondary)
                    }
                }
            }
            .padding(DayliSpacing.screenMargin)
        }
        .dayliScreenBackground()
        .navigationTitle("Meta")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Editar") { editing = true }
                    Button("Excluir", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { manualValue = goal.currentValue }
        .sheet(isPresented: $editing) { GoalEditorView(goal: goal) }
        .confirmationDialog("Excluir esta meta?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                env.repository.delete(goal)
                dismiss()
            }
        }
    }
}

struct GoalEditorView: View {
    let goal: Goal?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @State private var draft = GoalDraft()
    @State private var newMilestone = ""
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Qual é a sua meta?", text: $draft.title).font(DayliFont.bodyLarge)
                        .accessibilityIdentifier("goal.title")
                    TextField("Por que ela é importante para você?", text: $draft.details, axis: .vertical).lineLimit(2...5)
                    CategoryPicker(categories: categories, selection: $draft.categoryID)
                }
                Section("Período") {
                    DatePicker("Início", selection: $draft.startDate, displayedComponents: .date)
                    DatePicker("Prazo", selection: $draft.endDate, in: draft.startDate..., displayedComponents: .date)
                }
                Section {
                    Picker("Como medir", selection: $draft.progressKind) {
                        ForEach(GoalProgressKind.allCases) { Text($0.title).tag($0) }
                    }
                    switch draft.progressKind {
                    case .manual:
                        HStack {
                            Text("Alvo")
                            TextField("Valor", value: $draft.targetValue, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        TextField("Unidade (ex.: horas, livros)", text: $draft.unit)
                    case .milestones:
                        ForEach(Array(draft.milestones.enumerated()), id: \.offset) { index, title in
                            Text(title)
                                .swipeActions { Button("Remover", role: .destructive) { draft.milestones.remove(at: index) } }
                        }
                        HStack {
                            TextField("Nova etapa", text: $newMilestone).onSubmit(addMilestone)
                            Button("Adicionar", action: addMilestone)
                        }
                    case .linkedHabit:
                        Picker("Hábito", selection: $draft.linkedHabitID) {
                            Text("Escolha um hábito").tag(UUID?.none)
                            ForEach(habits) { Text($0.title).tag(UUID?.some($0.id)) }
                        }
                        HStack {
                            Text("Dias cumpridos para atingir")
                            TextField("Alvo", value: $draft.targetValue, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Progresso")
                } footer: {
                    Text(footer)
                }
                if let errorMessage { Section { InlineNotice(style: .error, message: errorMessage) } }
            }
            .scrollContentBackground(.hidden)
            .dayliScreenBackground()
            .navigationTitle(goal == nil ? "Nova meta" : "Editar meta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save).fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || (draft.progressKind == .linkedHabit && draft.linkedHabitID == nil))
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let goal { draft = GoalDraft(goal: goal) }
            }
        }
    }

    private var footer: String {
        switch draft.progressKind {
        case .manual: return "Você atualiza o valor atual quando quiser."
        case .milestones: return "O progresso é a proporção de etapas concluídas."
        case .linkedHabit: return "Somente o hábito escolhido conta para esta meta — nada é somado automaticamente sem vínculo."
        }
    }

    private func addMilestone() {
        guard let title = InputValidator.sanitizedTitle(newMilestone) else { return }
        draft.milestones.append(title)
        newMilestone = ""
    }

    private func save() {
        do {
            if let goal { try env.repository.updateGoal(goal, from: draft) } else { try env.repository.createGoal(from: draft) }
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
