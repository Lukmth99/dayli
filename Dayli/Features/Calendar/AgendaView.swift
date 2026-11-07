import SwiftUI
import SwiftData
import DayliCore

struct AgendaView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: return "Dia"
            case .week: return "Semana"
            case .month: return "Mês"
            }
        }
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]
    @Query private var events: [CalendarEvent]
    @Query private var tasks: [TaskItem]

    @State private var mode: Mode = .day
    @State private var selectedDate = Calendar.dayli.startOfDay(for: .now)
    @State private var hiddenCategoryIDs: Set<UUID> = []
    @State private var showExternal = true
    @State private var editingEvent: CalendarEvent?
    @State private var editingTask: TaskItem?
    @State private var selectedExternal: TimelineEntry?
    @State private var newEventDate: Date?

    private var calendar: Calendar { .dayli }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider().overlay(DayliColor.divider)
                ScrollView {
                    switch mode {
                    case .day: dayView(selectedDate)
                    case .week: weekView
                    case .month: monthView
                    }
                }
            }
            .dayliScreenBackground()
            .navigationTitle("Agenda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newEventDate = defaultNewEventStart } label: { Image(systemName: "calendar.badge.plus") }
                        .accessibilityLabel("Novo compromisso")
                }
            }
            .sheet(item: $editingEvent) { EventEditorView(event: $0) }
            .sheet(item: $editingTask) { TaskEditorView(task: $0) }
            .sheet(item: $selectedExternal) { ExternalEventDetailView(entry: $0) }
            .sheet(isPresented: Binding(get: { newEventDate != nil }, set: { if !$0 { newEventDate = nil } })) {
                EventEditorView(event: nil, initialStart: newEventDate ?? .now)
            }
        }
    }

    private var defaultNewEventStart: Date {
        let now = Date.now
        let base = calendar.isDate(selectedDate, inSameDayAs: now) ? now : TimeOfDay(hour: 9).date(on: selectedDate, calendar: calendar)
        return calendar.nextDate(after: base, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? base
    }

    // MARK: Controles

    private var controls: some View {
        VStack(spacing: DayliSpacing.sm) {
            Picker("Visualização", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Anterior")
                Spacer()
                VStack(spacing: 2) {
                    Text(periodTitle).font(DayliFont.headlineSmall)
                    if !calendar.isDate(selectedDate, inSameDayAs: .now) {
                        Button("Voltar para hoje") { selectedDate = calendar.startOfDay(for: .now) }
                            .font(DayliFont.caption)
                    }
                }
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Próximo")
            }
            .foregroundStyle(DayliColor.textPrimary)

            if mode != .month { weekStrip }
        }
        .padding(.horizontal, DayliSpacing.screenMargin)
        .padding(.vertical, DayliSpacing.sm)
    }

    private var periodTitle: String {
        switch mode {
        case .day: return DayliFormat.weekdayDayMonth(selectedDate).capitalized
        case .week:
            let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate)!
            return "\(DayliFormat.dayMonth(week.start)) – \(DayliFormat.dayMonth(calendar.addingDays(-1, to: week.end)))"
        case .month: return DayliFormat.monthYear(selectedDate)
        }
    }

    private func shift(_ direction: Int) {
        Haptics.selection()
        let component: Calendar.Component = mode == .day ? .day : (mode == .week ? .weekOfYear : .month)
        selectedDate = calendar.date(byAdding: component, value: direction, to: selectedDate) ?? selectedDate
    }

    private var weekStrip: some View {
        let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate)!
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.addingDays(offset, to: week.start)
                let selected = calendar.isDate(day, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(day)
                Button {
                    selectedDate = day
                    if mode == .week { mode = .day }
                } label: {
                    VStack(spacing: 4) {
                        Text(DayliFormat.shortWeekday(day).prefix(3).uppercased())
                            .font(DayliFont.caption)
                        Text("\(calendar.component(.day, from: day))")
                            .font(DayliFont.headlineSmall)
                        Circle().fill(hasItems(on: day) ? DayliColor.lavender : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(selected ? DayliColor.onPrimary : (isToday ? DayliColor.lavenderInk : DayliColor.textPrimary))
                    .background(selected ? DayliColor.primary : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DayliFormat.weekdayDayMonth(day))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Eventos do Calendário Apple", isOn: $showExternal)
                .disabled(!env.calendarService.accessState.canRead)
            Section("Categorias") {
                ForEach(categories) { category in
                    Toggle(category.name, isOn: Binding(
                        get: { !hiddenCategoryIDs.contains(category.id) },
                        set: { if $0 { hiddenCategoryIDs.remove(category.id) } else { hiddenCategoryIDs.insert(category.id) } }))
                }
            }
        } label: {
            Image(systemName: hiddenCategoryIDs.isEmpty && showExternal ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filtrar categorias")
    }

    // MARK: Dados

    private func entries(for day: Date) -> [TimelineEntry] {
        _ = env.dataVersion
        _ = env.calendarService.changeToken
        _ = events.count + tasks.count
        return env.dayContextBuilder.context(for: day).entries.filter { entry in
            if entry.kind == .externalEvent { return showExternal }
            if let id = entry.categoryID { return !hiddenCategoryIDs.contains(id) }
            return true
        }
    }

    private func hasItems(on day: Date) -> Bool {
        let interval = calendar.dayInterval(for: day)
        if events.contains(where: { !$0.occurrenceStarts(in: interval, calendar: calendar).isEmpty }) { return true }
        return tasks.contains { !$0.isCompleted && $0.dueDate.map { interval.includes($0) } == true }
    }

    private func category(_ id: UUID?) -> LifeCategory? {
        id.flatMap { id in categories.first { $0.id == id } }
    }

    // MARK: Visualizações

    @ViewBuilder
    private func dayView(_ day: Date) -> some View {
        let items = entries(for: day)
        let conflicts = ConflictDetector.allConflicts(env.dayContextBuilder.busyIntervals(from: items))
        VStack(alignment: .leading, spacing: 10) {
            if !conflicts.isEmpty {
                InlineNotice(style: .warning, message: conflicts.count == 1
                             ? "Há um conflito de horário: \(conflicts[0].first.title) e \(conflicts[0].second.title)."
                             : "Há \(conflicts.count) conflitos de horário neste dia.")
            }
            if items.isEmpty {
                EmptyStateView(systemImage: "calendar", title: "Dia livre",
                               message: "Nenhum compromisso ou tarefa para este dia.",
                               actionTitle: "Novo compromisso") { newEventDate = defaultNewEventStart }
            } else {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items) { entry in
                            if calendar.isDateInToday(day), !entry.isAllDay, entry.start > context.date,
                               items.firstIndex(where: { !$0.isAllDay && $0.start > context.date }) == items.firstIndex(of: entry) {
                                nowIndicator(context.date)
                            }
                            TimelineRow(entry: entry, category: category(entry.categoryID), now: context.date,
                                        onToggle: { toggle(entry) }, onOpen: { open(entry) })
                        }
                    }
                }
            }
        }
        .padding(DayliSpacing.screenMargin)
    }

    private func nowIndicator(_ now: Date) -> some View {
        HStack(spacing: 6) {
            Circle().fill(DayliColor.rose).frame(width: 8, height: 8)
            Text("Agora · \(DayliFormat.time(now))").font(DayliFont.caption).foregroundStyle(DayliColor.roseInk)
            Rectangle().fill(DayliColor.rose).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var weekView: some View {
        let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate)!
        return VStack(alignment: .leading, spacing: DayliSpacing.md) {
            ForEach(0..<7, id: \.self) { offset in
                let day = calendar.addingDays(offset, to: week.start)
                let items = entries(for: day)
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        selectedDate = day
                        mode = .day
                    } label: {
                        HStack {
                            Text(DayliFormat.weekdayDayMonth(day).capitalized)
                                .font(DayliFont.headlineSmall)
                                .foregroundStyle(calendar.isDateInToday(day) ? DayliColor.lavenderInk : DayliColor.textPrimary)
                            Spacer()
                            Text(items.isEmpty ? "Livre" : "\(items.count) \(items.count == 1 ? "item" : "itens")")
                                .font(DayliFont.caption)
                                .foregroundStyle(DayliColor.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(items.prefix(6)) { entry in
                        TimelineRow(entry: entry, category: category(entry.categoryID), now: .now,
                                    onToggle: { toggle(entry) }, onOpen: { open(entry) })
                    }
                    if items.count > 6 {
                        Text("+ \(items.count - 6) itens").font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                    }
                }
            }
        }
        .padding(DayliSpacing.screenMargin)
    }

    private var monthView: some View {
        VStack(spacing: DayliSpacing.md) {
            MonthGrid(month: selectedDate, selected: $selectedDate, hasItems: hasItems(on:))
            dayView(selectedDate)
        }
        .padding(.top, DayliSpacing.sm)
    }

    // MARK: Ações

    private func toggle(_ entry: TimelineEntry) {
        guard entry.kind == .task, let id = UUID(uuidString: entry.sourceID), let task = env.repository.task(id: id) else { return }
        withAnimation { env.repository.toggleCompletion(task) }
    }

    private func open(_ entry: TimelineEntry) {
        switch entry.kind {
        case .task: editingTask = UUID(uuidString: entry.sourceID).flatMap { env.repository.task(id: $0) }
        case .event: editingEvent = UUID(uuidString: entry.sourceID).flatMap { env.repository.event(id: $0) }
        case .externalEvent: selectedExternal = entry
        }
    }
}

struct MonthGrid: View {
    let month: Date
    @Binding var selected: Date
    let hasItems: (Date) -> Bool

    private var calendar: Calendar { .dayli }

    var body: some View {
        let interval = calendar.dateInterval(of: .month, for: month)!
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    let weekday = (calendar.firstWeekday - 1 + i) % 7 + 1
                    Text(RecurrenceRule.shortWeekdayName(weekday).prefix(1).uppercased())
                        .font(DayliFont.caption)
                        .foregroundStyle(DayliColor.textSecondary)
                        .accessibilityHidden(true)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(0..<days, id: \.self) { offset in
                    let day = calendar.addingDays(offset, to: interval.start)
                    let isSelected = calendar.isDate(day, inSameDayAs: selected)
                    Button { selected = day } label: {
                        VStack(spacing: 2) {
                            Text("\(offset + 1)").font(DayliFont.bodyMedium)
                            Circle().fill(hasItems(day) ? DayliColor.lavender : .clear).frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isSelected ? DayliColor.onPrimary : (calendar.isDateInToday(day) ? DayliColor.lavenderInk : DayliColor.textPrimary))
                        .background(isSelected ? DayliColor.primary : .clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(DayliFormat.weekdayDayMonth(day) + (hasItems(day) ? ", com itens" : ""))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .dayliCard()
        .padding(.horizontal, DayliSpacing.screenMargin)
    }
}
