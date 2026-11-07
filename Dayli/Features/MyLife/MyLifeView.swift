import SwiftUI
import SwiftData
import DayliCore

enum MyLifeRoute: Hashable {
    case area(LifeArea)
    case habits
    case habit(UUID)
    case goals
    case goal(UUID)
}

/// "Minha Vida": visão das dimensões da vida, derivada apenas dos dados existentes.
struct MyLifeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Query private var settingsList: [AppSettings]
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.createdAt) private var habits: [Habit]
    @Query(sort: \Goal.endDate) private var goals: [Goal]
    @Query private var tasks: [TaskItem]
    @Query private var events: [CalendarEvent]
    @State private var path: [MyLifeRoute] = []

    private var areas: [LifeArea] {
        let selected = settingsList.first?.selectedAreas ?? Set(LifeArea.allCases)
        return LifeArea.allCases.filter { $0 != .habits && selected.contains($0) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DayliSpacing.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PANORAMA SEMANAL").font(DayliFont.caption).tracking(0.8).foregroundStyle(DayliColor.lavenderInk)
                        Text("Seu equilíbrio").font(DayliFont.headlineLarge).foregroundStyle(DayliColor.textPrimary)
                        Text("Um olhar gentil sobre cada área da sua vida nesta semana.")
                            .font(DayliFont.bodyMedium).foregroundStyle(DayliColor.textSecondary)
                    }
                    SectionHeader(title: "Suas dimensões", trailing: "\(areas.count) áreas")
                    ForEach(areas) { area in
                        NavigationLink(value: MyLifeRoute.area(area)) { areaCard(area) }
                            .buttonStyle(.plain)
                    }
                    habitsCard
                    goalsCard
                    Text("“Não se trata de equilibrar tudo perfeitamente todos os dias, mas de acolher cada dimensão no seu tempo.”")
                        .font(DayliFont.bodySmall.italic())
                        .foregroundStyle(DayliColor.textSecondary)
                        .padding(DayliSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DayliColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(DayliSpacing.screenMargin)
            }
            .dayliScreenBackground()
            .navigationTitle("Minha Vida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { QuickAddToolbarButton() }
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.sheet = .review } label: { Image(systemName: "chart.bar.xaxis") }
                        .accessibilityLabel("Resumo semanal")
                }
            }
            .navigationDestination(for: MyLifeRoute.self) { route in
                switch route {
                case .area(let area): AreaDetailView(area: area)
                case .habits: HabitsView()
                case .habit(let id):
                    if let habit = habits.first(where: { $0.id == id }) { HabitDetailView(habit: habit) } else { missing }
                case .goals: GoalsView()
                case .goal(let id):
                    if let goal = goals.first(where: { $0.id == id }) { GoalDetailView(goal: goal) } else { missing }
                }
            }
        }
    }

    private var missing: some View {
        EmptyStateView(systemImage: "questionmark.circle", title: "Item não encontrado", message: "Ele pode ter sido excluído.")
    }

    // MARK: Cartões

    private func areaStats(_ area: LifeArea) -> (pending: Int, doneThisWeek: Int, upcomingEvents: Int, goals: Int) {
        let calendar = Calendar.dayli
        let week = calendar.dateInterval(of: .weekOfYear, for: .now) ?? calendar.dayInterval(for: .now)
        let areaTasks = tasks.filter { $0.category?.area == area }
        let pending = areaTasks.filter { !$0.isCompleted }.count
        let done = areaTasks.filter { $0.completedAt.map { week.includes($0) } == true }.count
        let next7 = DateInterval(start: .now, end: calendar.addingDays(7, to: .now))
        let upcoming = events.filter { $0.category?.area == area }.reduce(0) { $0 + $1.occurrenceStarts(in: next7, calendar: calendar).count }
        let areaGoals = goals.filter { $0.category?.area == area && $0.status == .active }.count
        return (pending, done, upcoming, areaGoals)
    }

    private func areaCard(_ area: LifeArea) -> some View {
        let stats = areaStats(area)
        let hex = DefaultCategory.all.first { $0.area == area }?.colorHex ?? "#B8A3CE"
        return VStack(alignment: .leading, spacing: DayliSpacing.sm) {
            HStack(spacing: 12) {
                Image(systemName: area.symbolName)
                    .foregroundStyle(DayliColor.ink(for: hex))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: hex).opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.title).font(DayliFont.headlineSmall).foregroundStyle(DayliColor.textPrimary)
                    Text(subtitle(area)).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(DayliColor.textSecondary)
            }
            HStack(spacing: DayliSpacing.sm) {
                miniStat("\(stats.pending)", "pendentes")
                miniStat("\(stats.doneThisWeek)", "feitas na semana")
                miniStat("\(stats.upcomingEvents)", "compromissos (7 dias)")
            }
        }
        .dayliCard()
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ area: LifeArea) -> String {
        switch area {
        case .work: return "Demandas, entregas e reuniões"
        case .studies: return "Matérias, sessões e provas"
        case .fitness: return "Treinos e frequência"
        case .health: return "Autocuidado e hábitos saudáveis"
        case .personal: return "Planos, eventos e datas especiais"
        case .relationship: return "Momentos a dois e afeto"
        case .habits: return "Rotinas"
        }
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(DayliFont.headlineSmall).monospacedDigit()
            Text(label).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DayliColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var habitsCard: some View {
        let calendar = Calendar.dayli
        let today = calendar.startOfDay(for: .now)
        let scheduled = habits.filter { $0.schedule.isScheduled(on: today, calendar: calendar) }
        let done = scheduled.filter { env.repository.count(for: $0, on: today) >= $0.targetCount }
        return NavigationLink(value: MyLifeRoute.habits) {
            VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                HStack {
                    Label("Hábitos", systemImage: "arrow.triangle.2.circlepath").font(DayliFont.headlineSmall)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(DayliColor.textSecondary)
                }
                if habits.isEmpty {
                    Text("Crie seu primeiro hábito.").font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
                } else {
                    Text("\(done.count) de \(scheduled.count) feitos hoje").font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
                    ForEach(habits.prefix(4)) { habit in
                        let isDone = env.repository.count(for: habit, on: today) >= habit.targetCount
                        HStack {
                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isDone ? Color(hex: habit.colorHex) : DayliColor.divider)
                            Text(habit.title).font(DayliFont.bodyMedium)
                            Spacer()
                        }
                    }
                }
            }
            .foregroundStyle(DayliColor.textPrimary)
            .dayliCard()
        }
        .buttonStyle(.plain)
    }

    private var goalsCard: some View {
        let active = goals.filter { $0.status == .active }
        let completedThisMonth = goals.filter { $0.status == .completed && Calendar.dayli.isDate($0.endDate, equalTo: .now, toGranularity: .month) }
        return NavigationLink(value: MyLifeRoute.goals) {
            VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                HStack {
                    Label("Metas", systemImage: "flag").font(DayliFont.headlineSmall)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(DayliColor.textSecondary)
                }
                if active.isEmpty && completedThisMonth.isEmpty {
                    Text("Defina uma meta para acompanhar seu progresso.").font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
                } else {
                    Text("\(active.count) em andamento · \(completedThisMonth.count) concluída(s) neste mês")
                        .font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
                    ForEach(active.prefix(3)) { goal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.title).font(DayliFont.bodyMedium)
                            DayliProgressBar(value: goal.progress(calendar: .dayli), tint: Color(hex: goal.category?.colorHex ?? "#B8A3CE"))
                        }
                    }
                }
            }
            .foregroundStyle(DayliColor.textPrimary)
            .dayliCard()
        }
        .buttonStyle(.plain)
    }
}

/// Detalhe de uma área: tarefas, compromissos, metas e hábitos das categorias da área.
struct AreaDetailView: View {
    let area: LifeArea
    @Environment(AppEnvironment.self) private var env
    @Query private var tasks: [TaskItem]
    @Query private var events: [CalendarEvent]
    @Query(sort: \Goal.endDate) private var goals: [Goal]
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @State private var editingTask: TaskItem?
    @State private var editingEvent: CalendarEvent?

    var body: some View {
        let calendar = Calendar.dayli
        let pending = tasks.filter { $0.category?.area == area && !$0.isCompleted }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let range = DateInterval(start: calendar.startOfDay(for: .now), end: calendar.addingDays(14, to: .now))
        let upcoming = events.filter { $0.category?.area == area }
            .flatMap { e in e.occurrenceStarts(in: range, calendar: calendar).map { (event: e, start: $0) } }
            .sorted { $0.start < $1.start }
        let areaGoals = goals.filter { $0.category?.area == area && $0.status != .archived }
        let areaHabits = habits.filter { $0.category?.area == area }

        ScrollView {
            VStack(alignment: .leading, spacing: DayliSpacing.lg) {
                if area == .work {
                    InlineNotice(style: .info, message: "Registre apenas lembretes pessoais de trabalho. Não inclua dados de clientes, contas ou informações confidenciais do banco.")
                }
                if area == .health || area == .fitness {
                    InlineNotice(style: .info, message: "O Dayli ajuda a organizar sua rotina, mas não oferece orientação médica.")
                }

                section(title: "Pendências", count: pending.count) {
                    if pending.isEmpty { emptyLine("Nada pendente nesta área.") }
                    ForEach(pending.prefix(20)) { task in
                        TaskRow(task: task, onToggle: { env.repository.toggleCompletion(task) }, onOpen: { editingTask = task })
                    }
                }
                section(title: "Próximos compromissos", count: upcoming.count) {
                    if upcoming.isEmpty { emptyLine("Nenhum compromisso nos próximos 14 dias.") }
                    ForEach(Array(upcoming.prefix(20).enumerated()), id: \.offset) { _, item in
                        Button { editingEvent = item.event } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.event.title).font(DayliFont.bodyMedium.weight(.medium))
                                    Text("\(DayliFormat.relativeDay(item.start)) · \(item.event.isAllDay ? "Dia todo" : DayliFormat.time(item.start))")
                                        .font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                                }
                                Spacer()
                            }
                            .foregroundStyle(DayliColor.textPrimary)
                            .dayliCard(padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                section(title: "Metas", count: areaGoals.count) {
                    if areaGoals.isEmpty { emptyLine("Nenhuma meta nesta área.") }
                    ForEach(areaGoals) { goal in
                        NavigationLink(value: MyLifeRoute.goal(goal.id)) { GoalCard(goal: goal) }.buttonStyle(.plain)
                    }
                }
                section(title: "Hábitos", count: areaHabits.count) {
                    if areaHabits.isEmpty { emptyLine("Nenhum hábito nesta área.") }
                    ForEach(areaHabits) { habit in
                        NavigationLink(value: MyLifeRoute.habit(habit.id)) { HabitCard(habit: habit) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(DayliSpacing.screenMargin)
        }
        .dayliScreenBackground()
        .navigationTitle(area.title)
        .sheet(item: $editingTask) { TaskEditorView(task: $0) }
        .sheet(item: $editingEvent) { EventEditorView(event: $0) }
    }

    private func section<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DayliSpacing.sm) {
            SectionHeader(title: title, trailing: "\(count)")
            content()
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
    }
}
