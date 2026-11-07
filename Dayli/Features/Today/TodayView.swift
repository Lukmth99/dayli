import SwiftUI
import SwiftData
import DayliCore

struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Query private var profiles: [UserProfile]
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]
    // Observadas para que a tela se atualize quando tarefas/eventos mudarem.
    @Query private var tasks: [TaskItem]
    @Query private var events: [CalendarEvent]

    @State private var editingTask: TaskItem?
    @State private var editingEvent: CalendarEvent?
    @State private var selectedExternal: TimelineEntry?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let context = makeContext(now: now)
                ScrollView {
                    VStack(alignment: .leading, spacing: DayliSpacing.lg) {
                        header(now: now)
                        summaryCard(context: context, now: now)
                        organizeCard
                        timelineSection(context: context, now: now)
                        quickActions
                    }
                    .padding(.horizontal, DayliSpacing.screenMargin)
                    .padding(.bottom, DayliSpacing.xl)
                }
            }
            .dayliScreenBackground()
            .navigationTitle("Hoje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { QuickAddToolbarButton() }
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.sheet = .review } label: { Image(systemName: "chart.bar.xaxis") }
                        .accessibilityLabel("Resumo do dia e da semana")
                }
            }
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
            .sheet(item: $editingEvent) { EventEditorView(event: $0) }
            .sheet(item: $selectedExternal) { ExternalEventDetailView(entry: $0) }
        }
    }

    private func makeContext(now: Date) -> DayContextBuilder.DayContext {
        // Dependências observadas: alterações nesses valores redesenham a tela.
        _ = env.dataVersion
        _ = env.calendarService.changeToken
        _ = tasks.count + events.count
        return env.dayContextBuilder.context(for: now, now: now)
    }

    private func category(_ id: UUID?) -> LifeCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    // MARK: Cabeçalho

    private func header(now: Date) -> some View {
        let calendar = Calendar.dayli
        let profile = profiles.first
        let name = profile?.name.split(separator: " ").first.map(String.init) ?? ""
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(DayliFormat.weekdayDayMonth(now).uppercased())
                    .font(DayliFont.caption)
                    .tracking(0.8)
                    .foregroundStyle(DayliColor.lavenderInk)
                Text("\(Greeting.salutation(for: now, calendar: calendar))\(name.isEmpty ? "" : ", \(name)") \(Greeting.emoji(for: now, calendar: calendar))")
                    .font(DayliFont.headlineLarge)
                    .foregroundStyle(DayliColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(Greeting.message(for: now, calendar: calendar))
                    .font(DayliFont.bodyMedium)
                    .foregroundStyle(DayliColor.textSecondary)
            }
            Spacer()
            Button { router.selectedTab = .profile } label: {
                AvatarView(initials: profile?.initials ?? "D", photoData: profile?.photoData, size: 48)
            }
            .accessibilityLabel("Abrir perfil")
        }
        .padding(.top, DayliSpacing.sm)
    }

    // MARK: Resumo

    private func summaryCard(context: DayContextBuilder.DayContext, now: Date) -> some View {
        let eventsToday = context.entries.filter { $0.kind != .task }.count
        return VStack(alignment: .leading, spacing: DayliSpacing.md) {
            HStack {
                Label("Panorama do dia", systemImage: "circle.dashed")
                    .font(DayliFont.headlineSmall)
                Spacer()
                InfoPill(text: "\(context.progress.percent)% concluído")
            }
            DayliProgressBar(value: context.progress.fraction)
            HStack {
                Text(context.progress.total == 0 ? "Nenhuma tarefa para hoje" : "\(context.progress.completed) de \(context.progress.total) tarefas concluídas")
                Spacer()
                Text("Ritmo consciente")
            }
            .font(DayliFont.bodySmall)
            .foregroundStyle(DayliColor.textSecondary)

            HStack(spacing: DayliSpacing.sm) {
                statTile(value: "\(eventsToday)", label: "Compromissos", icon: "calendar")
                statTile(value: "\(context.progress.completed)/\(context.progress.total)", label: "Realizadas", icon: "checkmark.circle")
                statTile(value: "\(context.progress.pending)", label: "Pendentes", icon: "circle")
            }

            if let next = context.nextEvent {
                Button { open(next) } label: {
                    HStack(spacing: 12) {
                        Capsule().fill(Color(hex: category(next.categoryID)?.colorHex ?? "#9BB8CD")).frame(width: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.start <= now ? "Agora" : "Próximo · \(DayliFormat.time(next.start))")
                                .font(DayliFont.caption)
                                .foregroundStyle(DayliColor.textSecondary)
                            Text(next.title)
                                .font(DayliFont.headlineSmall)
                                .foregroundStyle(DayliColor.textPrimary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DayliColor.textSecondary)
                    }
                    .padding(12)
                    .background(DayliColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Próximo compromisso: \(next.title), às \(DayliFormat.time(next.start))")
            }
        }
        .dayliCard(padding: 20, elevated: true)
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).imageScale(.small).accessibilityHidden(true)
                Text(value).font(DayliFont.headlineMedium).monospacedDigit()
            }
            Text(label).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(DayliColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var organizeCard: some View {
        Button { router.sheet = .planner(.now) } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .frame(width: 40, height: 40)
                    .background(DayliColor.lavender.opacity(0.3), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Organizar meu dia").font(DayliFont.headlineSmall)
                    Text("Encaixe suas tarefas nos horários livres, com pausas.")
                        .font(DayliFont.bodySmall)
                        .foregroundStyle(DayliColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(DayliColor.textSecondary)
            }
            .foregroundStyle(DayliColor.textPrimary)
            .padding(DayliSpacing.md)
            .background(
                LinearGradient(colors: [DayliColor.lavender.opacity(0.22), DayliColor.rose.opacity(0.12)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: DayliRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.organize")
    }

    // MARK: Linha do tempo

    @ViewBuilder
    private func timelineSection(context: DayContextBuilder.DayContext, now: Date) -> some View {
        let timed = context.entries.filter { !$0.isAllDay }
        let untimed = context.entries.filter { $0.isAllDay }

        VStack(alignment: .leading, spacing: DayliSpacing.md) {
            SectionHeader(title: "Cronograma", trailing: "Hoje")
            if context.entries.isEmpty {
                EmptyStateView(systemImage: "sun.haze", title: "Um dia em branco",
                               message: "Adicione uma tarefa ou compromisso quando quiser. Sem pressa.",
                               actionTitle: "Nova tarefa") { router.sheet = .quickAdd(.task) }
                    .dayliCard()
            } else {
                if !timed.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(timed) { entry in
                            TimelineRow(entry: entry, category: category(entry.categoryID), now: now,
                                        onToggle: { toggle(entry) }, onOpen: { open(entry) })
                        }
                    }
                }
                if !untimed.isEmpty {
                    Text("Ao longo do dia")
                        .font(DayliFont.headlineSmall)
                        .foregroundStyle(DayliColor.textPrimary)
                        .padding(.top, DayliSpacing.sm)
                    VStack(spacing: 10) {
                        ForEach(untimed) { entry in
                            TimelineRow(entry: entry, category: category(entry.categoryID), now: now,
                                        onToggle: { toggle(entry) }, onOpen: { open(entry) })
                        }
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: DayliSpacing.sm) {
            SectionHeader(title: "Registrar rápido")
            HStack(spacing: DayliSpacing.sm) {
                quickButton("Nova tarefa", icon: "checkmark.circle", tint: DayliColor.sage) { router.sheet = .quickAdd(.task) }
                quickButton("Compromisso", icon: "calendar.badge.plus", tint: DayliColor.lavender) { router.sheet = .quickAdd(.event) }
                quickButton("Novo hábito", icon: "leaf", tint: DayliColor.rose) { router.sheet = .quickAdd(.habit) }
            }
            Button { router.sheet = .assistant } label: {
                Label("Conversar com o assistente", systemImage: "bubble.left.and.text.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dayliSecondary)
            .padding(.top, DayliSpacing.xs)
        }
    }

    private func quickButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.25), in: Circle())
                Text(title).font(DayliFont.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(DayliColor.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DayliSpacing.md)
            .background(DayliColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DayliColor.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Ações

    private func toggle(_ entry: TimelineEntry) {
        guard entry.kind == .task, let id = UUID(uuidString: entry.sourceID), let task = env.repository.task(id: id) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            env.repository.toggleCompletion(task)
        }
    }

    private func open(_ entry: TimelineEntry) {
        switch entry.kind {
        case .task:
            if let id = UUID(uuidString: entry.sourceID) { editingTask = env.repository.task(id: id) }
        case .event:
            if let id = UUID(uuidString: entry.sourceID) { editingEvent = env.repository.event(id: id) }
        case .externalEvent:
            selectedExternal = entry
        }
    }
}
