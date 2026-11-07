import SwiftUI
import SwiftData
import DayliCore

// MARK: - Lista de hábitos

struct HabitsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.createdAt) private var habits: [Habit]
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DayliSpacing.md) {
                if habits.isEmpty {
                    EmptyStateView(systemImage: "leaf", title: "Nenhum hábito ainda",
                                   message: "Comece com algo pequeno, como beber água ou ler 10 páginas.",
                                   actionTitle: "Criar hábito") { creating = true }
                        .dayliCard()
                } else {
                    ForEach(habits) { habit in
                        NavigationLink(value: MyLifeRoute.habit(habit.id)) {
                            HabitCard(habit: habit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(DayliSpacing.screenMargin)
        }
        .dayliScreenBackground()
        .navigationTitle("Hábitos")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Novo hábito")
            }
        }
        .sheet(isPresented: $creating) { HabitEditorView(habit: nil) }
    }
}

/// Cartão com registro rápido do dia e a semana atual.
struct HabitCard: View {
    let habit: Habit
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let calendar = Calendar.dayli
        let today = calendar.startOfDay(for: .now)
        let counts = env.repository.counts(for: habit)
        let calc = HabitCalculator(calendar: calendar)
        let todayCount = counts[today] ?? 0
        let done = calc.isDayComplete(count: todayCount, target: habit.targetCount)
        let scheduledToday = habit.schedule.isScheduled(on: today, calendar: calendar)
        let streak = calc.currentStreak(schedule: habit.schedule, target: habit.targetCount, counts: counts, createdAt: habit.createdAt, today: .now)
        let week = calc.weekProgress(schedule: habit.schedule, target: habit.targetCount, counts: counts, today: .now)

        HStack(spacing: 12) {
            Image(systemName: habit.symbolName)
                .font(.title3)
                .foregroundStyle(DayliColor.ink(for: habit.colorHex))
                .frame(width: 44, height: 44)
                .background(Color(hex: habit.colorHex).opacity(0.2), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title).font(DayliFont.headlineSmall).foregroundStyle(DayliColor.textPrimary)
                HStack(spacing: 8) {
                    Text(habit.schedule.summary)
                    if streak.value > 0 { Text("· \(streak.description)") }
                }
                .font(DayliFont.caption)
                .foregroundStyle(DayliColor.textSecondary)
                Text("Semana: \(week.done) de \(week.expected)")
                    .font(DayliFont.caption)
                    .foregroundStyle(DayliColor.textSecondary)
            }
            Spacer()
            if habit.targetCount > 1 {
                Button {
                    Haptics.light()
                    env.repository.log(habit, on: .now)
                } label: {
                    VStack(spacing: 0) {
                        Text("\(todayCount)/\(habit.targetCount)").font(DayliFont.label).monospacedDigit()
                        if !habit.unit.isEmpty { Text(habit.unit).font(DayliFont.caption) }
                    }
                    .frame(minWidth: 56, minHeight: 44)
                    .foregroundStyle(done ? Color.white : DayliColor.textPrimary)
                    .background(done ? Color(hex: habit.colorHex) : DayliColor.surfaceMuted, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Registrar mais um em \(habit.title). Hoje: \(todayCount) de \(habit.targetCount)")
            } else {
                CompletionCircle(isCompleted: done, colorHex: habit.colorHex) {
                    env.repository.toggle(habit, on: .now)
                }
                .accessibilityLabel(done ? "\(habit.title) feito hoje" : "Marcar \(habit.title) como feito hoje")
            }
        }
        .opacity(scheduledToday || done ? 1 : 0.7)
        .dayliCard()
    }
}

// MARK: - Detalhe

struct HabitDetailView: View {
    let habit: Habit
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        let calendar = Calendar.dayli
        let counts = env.repository.counts(for: habit)
        let calc = HabitCalculator(calendar: calendar)
        let streak = calc.currentStreak(schedule: habit.schedule, target: habit.targetCount, counts: counts, createdAt: habit.createdAt, today: .now)
        let consistency = calc.consistency(schedule: habit.schedule, target: habit.targetCount, counts: counts, createdAt: habit.createdAt, today: .now)

        ScrollView {
            VStack(alignment: .leading, spacing: DayliSpacing.lg) {
                HabitCard(habit: habit)
                HStack(spacing: DayliSpacing.sm) {
                    metric(title: "Sequência", value: streak.description)
                    metric(title: "Consistência (30 dias)", value: "\(Int((consistency * 100).rounded()))%")
                }
                VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                    SectionHeader(title: "Calendário de consistência", trailing: "Últimas 12 semanas")
                    ConsistencyGrid(habit: habit, counts: counts)
                    Text("Toque em um dia passado para registrar ou desfazer.")
                        .font(DayliFont.caption)
                        .foregroundStyle(DayliColor.textSecondary)
                }
                .dayliCard()
                if habit.schedule != .daily {
                    InlineNotice(style: .info, message: "Dias fora da programação não contam contra a sua sequência.")
                }
            }
            .padding(DayliSpacing.screenMargin)
        }
        .dayliScreenBackground()
        .navigationTitle(habit.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Editar") { editing = true }
                    Button("Arquivar") { env.repository.archive(habit); dismiss() }
                    Button("Excluir", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $editing) { HabitEditorView(habit: habit) }
        .confirmationDialog("Excluir este hábito e todo o histórico?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                env.repository.delete(habit)
                dismiss()
            }
        } message: {
            Text("Se preferir manter o histórico, use Arquivar.")
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
            Text(value).font(DayliFont.headlineSmall).foregroundStyle(DayliColor.textPrimary)
        }
        .dayliCard()
        .accessibilityElement(children: .combine)
    }
}

struct ConsistencyGrid: View {
    let habit: Habit
    let counts: [Date: Int]
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let calendar = Calendar.dayli
        let today = calendar.startOfDay(for: .now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let firstDay = calendar.addingDays(-7 * 11, to: weekStart)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 12)

        LazyVGrid(columns: columns, spacing: 4) {
            // Linhas = dias da semana; colunas = semanas.
            ForEach(0..<84, id: \.self) { index in
                let week = index % 12
                let weekday = index / 12
                let day = calendar.addingDays(week * 7 + weekday, to: firstDay)
                let count = counts[day] ?? 0
                let done = count >= habit.targetCount
                let scheduled = habit.schedule.isScheduled(on: day, calendar: calendar)
                let future = day > today
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(done ? Color(hex: habit.colorHex) : (scheduled ? DayliColor.surfaceMuted : DayliColor.surfaceMuted.opacity(0.4)))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(calendar.isDate(day, inSameDayAs: today) ? DayliColor.primary : .clear, lineWidth: 1))
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(future ? 0.25 : 1)
                    .onTapGesture {
                        guard !future, day >= calendar.startOfDay(for: habit.createdAt) || done else { return }
                        Haptics.selection()
                        env.repository.toggle(habit, on: day)
                    }
                    .accessibilityElement()
                    .accessibilityLabel("\(DayliFormat.weekdayDayMonth(day)): \(done ? "feito" : (scheduled ? "não registrado" : "não programado"))")
                    .accessibilityAddTraits(future ? [] : .isButton)
            }
        }
    }
}

// MARK: - Editor

struct HabitEditorView: View {
    let habit: Habit?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]
    @State private var draft = HabitDraft()
    @State private var errorMessage: String?
    @State private var loaded = false

    private let symbols = ["drop", "book", "figure.walk", "dumbbell", "bed.double", "brain.head.profile", "leaf", "cup.and.saucer", "pencil", "heart", "sun.max", "moon.stars"]
    private let suggestions = ["Beber água", "Ler", "Estudar", "Ir à academia", "Dormir no horário", "Meditar"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome do hábito", text: $draft.title)
                        .font(DayliFont.bodyLarge)
                        .accessibilityIdentifier("habit.title")
                    if habit == nil && draft.title.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { s in
                                    Button(s) { draft.title = s }
                                        .font(DayliFont.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(DayliColor.surfaceMuted, in: Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section("Aparência") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(symbols, id: \.self) { symbol in
                                Button { draft.symbolName = symbol } label: {
                                    Image(systemName: symbol)
                                        .frame(width: 40, height: 40)
                                        .background(draft.symbolName == symbol ? Color(hex: draft.colorHex).opacity(0.35) : DayliColor.surfaceMuted, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol)
                                .accessibilityAddTraits(draft.symbolName == symbol ? .isSelected : [])
                            }
                        }
                    }
                    ColorPalettePicker(selection: $draft.colorHex)
                    CategoryPicker(categories: categories, selection: $draft.categoryID)
                }
                Section {
                    Picker("Frequência", selection: $draft.scheduleKind) {
                        ForEach(HabitDraft.ScheduleKind.allCases) { Text($0.title).tag($0) }
                    }
                    switch draft.scheduleKind {
                    case .daily: EmptyView()
                    case .weekdays: WeekdayPicker(selection: $draft.weekdays).padding(.vertical, 4)
                    case .timesPerWeek: Stepper("\(draft.timesPerWeek) vezes por semana", value: $draft.timesPerWeek, in: 1...7)
                    }
                    Stepper("Meta diária: \(draft.targetCount)\(draft.unit.isEmpty ? "" : " \(draft.unit)")", value: $draft.targetCount, in: 1...100)
                    if draft.targetCount > 1 {
                        TextField("Unidade (ex.: copos, páginas)", text: $draft.unit)
                    }
                } header: {
                    Text("Frequência")
                } footer: {
                    Text("A sequência considera só os dias programados — dias de folga não quebram seu ritmo.")
                }
                Section("Lembrete") {
                    Toggle("Lembrar", isOn: $draft.hasReminder.animation())
                    if draft.hasReminder {
                        TimeOfDayPicker(title: "Horário", value: $draft.reminderTime)
                    }
                }
                if let errorMessage {
                    Section { InlineNotice(style: .error, message: errorMessage) }
                }
            }
            .scrollContentBackground(.hidden)
            .dayliScreenBackground()
            .navigationTitle(habit == nil ? "Novo hábito" : "Editar hábito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("habit.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let habit { draft = HabitDraft(habit: habit) }
            }
        }
    }

    private func save() {
        do {
            if let habit { try env.repository.updateHabit(habit, from: draft) } else { try env.repository.createHabit(from: draft) }
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
