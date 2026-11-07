import SwiftUI
import SwiftData
import Charts
import DayliCore

/// Revisão diária e semanal. Todos os indicadores derivam de dados existentes;
/// tarefas concluídas e eventos que apenas ocorreram são mostrados separadamente.
struct ReviewView: View {
    enum Period: String, CaseIterable, Identifiable {
        case day, week
        var id: String { rawValue }
        var title: String { self == .day ? "Hoje" : "Semana" }
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @Query private var events: [CalendarEvent]
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var habits: [Habit]
    @Query private var goals: [Goal]
    @State private var period: Period = .week

    private var calendar: Calendar { .dayli }

    private var interval: DateInterval {
        switch period {
        case .day: return calendar.dayInterval(for: .now)
        case .week: return calendar.dateInterval(of: .weekOfYear, for: .now) ?? calendar.dayInterval(for: .now)
        }
    }

    struct DayStat: Identifiable {
        let day: Date
        let completed: Int
        let habitDays: Int
        var id: Date { day }
    }

    var body: some View {
        let range = interval
        let now = Date.now
        let completed = tasks.filter { $0.isCompleted && ($0.completedAt.map { range.includes($0) } ?? false) }
        let pending = tasks.filter { !$0.isCompleted && ($0.dueDate.map { $0 < min(range.end, calendar.endOfDay(for: now)) } ?? false) }
        let rescheduled = tasks.filter { $0.rescheduleCount > 0 && range.includes($0.updatedAt) }
        let pastRange = DateInterval(start: range.start, end: max(range.start, min(range.end, now)))
        let eventsHappened = events.reduce(0) { total, event in
            total + event.occurrenceStarts(in: pastRange, calendar: calendar).filter { $0.addingTimeInterval(event.duration) <= now }.count
        }
        let externalHappened = env.calendarService.events(in: pastRange).filter { $0.end <= now }.count
        let habitEntries = habits.flatMap(\.entries).filter { entry in
            range.includes(entry.day) && (entry.habit.map { entry.count >= $0.targetCount } ?? false)
        }
        let activeGoals = goals.filter { $0.status == .active }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DayliSpacing.lg) {
                    Picker("Período", selection: $period) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        metric("Tarefas concluídas", "\(completed.count)", icon: "checkmark.circle", tint: DayliColor.sage)
                        metric("Pendentes", "\(pending.count)", icon: "circle.dashed", tint: DayliColor.peach)
                        metric("Compromissos realizados", "\(eventsHappened + externalHappened)", icon: "calendar", tint: DayliColor.softBlue,
                               footnote: "Eventos que já ocorreram — não contam como tarefas.")
                        metric("Hábitos registrados", "\(habitEntries.count)", icon: "leaf", tint: DayliColor.lavender)
                        metric("Reagendadas", "\(rescheduled.count)", icon: "arrow.uturn.right", tint: DayliColor.rose)
                        metric("Metas ativas", "\(activeGoals.count)", icon: "flag", tint: DayliColor.lavender)
                    }

                    if period == .week {
                        weekChart(range: range)
                    }

                    if !activeGoals.isEmpty {
                        VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                            SectionHeader(title: "Progresso das metas")
                            ForEach(activeGoals) { goal in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(goal.title).font(DayliFont.bodyMedium)
                                        Spacer()
                                        Text("\(Int((goal.progress(calendar: calendar) * 100).rounded()))%").font(DayliFont.caption).monospacedDigit()
                                    }
                                    DayliProgressBar(value: goal.progress(calendar: calendar), tint: Color(hex: goal.category?.colorHex ?? "#B8A3CE"))
                                }
                            }
                        }
                        .dayliCard()
                    }

                    VStack(alignment: .leading, spacing: DayliSpacing.sm) {
                        Text(reflection(completed: completed.count, pending: pending.count))
                            .font(DayliFont.bodyMedium)
                            .foregroundStyle(DayliColor.textPrimary)
                        Button {
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(400))
                                router.sheet = .planner(calendar.addingDays(1, to: calendar.startOfDay(for: .now)))
                            }
                        } label: {
                            Label("Planejar amanhã", systemImage: "moon.stars")
                        }
                        .buttonStyle(.dayliPrimary)
                    }
                    .dayliCard()
                }
                .padding(DayliSpacing.screenMargin)
            }
            .dayliScreenBackground()
            .navigationTitle("Revisão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func weekChart(range: DateInterval) -> some View {
        let stats: [DayStat] = (0..<7).map { offset in
            let day = calendar.addingDays(offset, to: range.start)
            let dayRange = calendar.dayInterval(for: day)
            let done = tasks.filter { $0.completedAt.map { dayRange.includes($0) } ?? false }.count
            let habitDays = habits.filter { h in h.entries.contains { $0.day == day && $0.count >= h.targetCount } }.count
            return DayStat(day: day, completed: done, habitDays: habitDays)
        }
        return VStack(alignment: .leading, spacing: DayliSpacing.sm) {
            SectionHeader(title: "Sua semana")
            Chart {
                ForEach(stats) { stat in
                    BarMark(x: .value("Dia", stat.day, unit: .day), y: .value("Quantidade", stat.completed))
                        .foregroundStyle(by: .value("Tipo", "Tarefas concluídas"))
                        .position(by: .value("Tipo", "Tarefas concluídas"))
                    BarMark(x: .value("Dia", stat.day, unit: .day), y: .value("Quantidade", stat.habitDays))
                        .foregroundStyle(by: .value("Tipo", "Hábitos cumpridos"))
                        .position(by: .value("Tipo", "Hábitos cumpridos"))
                }
            }
            .chartForegroundStyleScale(["Tarefas concluídas": DayliColor.sage, "Hábitos cumpridos": DayliColor.lavender])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 180)
            .accessibilityLabel("Gráfico de tarefas concluídas e hábitos cumpridos por dia")
        }
        .dayliCard()
    }

    private func metric(_ title: String, _ value: String, icon: String, tint: Color, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(value).font(DayliFont.headlineLarge).monospacedDigit()
            Text(title).font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
            if let footnote {
                Text(footnote).font(.system(size: 10)).foregroundStyle(DayliColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dayliCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private func reflection(completed: Int, pending: Int) -> String {
        switch (completed, pending) {
        case (0, 0): return "Um período leve. Descansar também é cuidar de si. 🌿"
        case (_, 0): return "Você concluiu tudo o que estava previsto. Que tal celebrar com calma?"
        case (0, _): return "Alguns dias são assim. Escolha uma coisa pequena para amanhã."
        default: return "Você concluiu \(completed) e ficaram \(pending) para depois — e está tudo bem reorganizar."
        }
    }
}
