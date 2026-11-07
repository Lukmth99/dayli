import Foundation
import SwiftData
import DayliCore

struct HabitDraft: Equatable {
    var title = ""
    var symbolName = "sparkles"
    var colorHex = "#A3B8A6"
    var scheduleKind: ScheduleKind = .daily
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var timesPerWeek = 3
    var targetCount = 1
    var unit = ""
    var hasReminder = false
    var reminderTime = TimeOfDay(hour: 20)
    var categoryID: UUID?

    enum ScheduleKind: String, CaseIterable, Identifiable {
        case daily, weekdays, timesPerWeek
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: return "Todo dia"
            case .weekdays: return "Dias específicos"
            case .timesPerWeek: return "Vezes por semana"
            }
        }
    }

    init() {}

    init(habit: Habit) {
        title = habit.title
        symbolName = habit.symbolName
        colorHex = habit.colorHex
        switch habit.schedule {
        case .daily: scheduleKind = .daily
        case .weekdays(let days): scheduleKind = .weekdays; weekdays = days
        case .timesPerWeek(let n): scheduleKind = .timesPerWeek; timesPerWeek = n
        }
        targetCount = habit.targetCount
        unit = habit.unit
        hasReminder = habit.reminderMinutes != nil
        reminderTime = TimeOfDay(minutesSinceMidnight: habit.reminderMinutes ?? 20 * 60)
        categoryID = habit.category?.id
    }

    var schedule: HabitSchedule {
        switch scheduleKind {
        case .daily: return .daily
        case .weekdays: return .weekdays(weekdays.isEmpty ? [2] : weekdays)
        case .timesPerWeek: return .timesPerWeek(min(max(timesPerWeek, 1), 7))
        }
    }
}

struct GoalDraft: Equatable {
    var title = ""
    var details = ""
    var categoryID: UUID?
    var startDate = Date.now
    var endDate = Calendar.dayli.date(byAdding: .month, value: 1, to: .now) ?? .now
    var progressKind: GoalProgressKind = .manual
    var targetValue: Double = 10
    var currentValue: Double = 0
    var unit = ""
    var linkedHabitID: UUID?
    var milestones: [String] = []

    init() {}

    init(goal: Goal) {
        title = goal.title
        details = goal.details
        categoryID = goal.category?.id
        startDate = goal.startDate
        endDate = goal.endDate
        progressKind = goal.progressKind
        targetValue = goal.targetValue ?? 10
        currentValue = goal.currentValue
        unit = goal.unit
        linkedHabitID = goal.linkedHabit?.id
        milestones = goal.sortedMilestones.map(\.title)
    }
}

extension DayliRepository {
    // MARK: Hábitos

    func activeHabits() -> [Habit] {
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func habit(id: UUID) -> Habit? {
        var descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    func createHabit(from draft: HabitDraft) throws -> Habit {
        guard let title = InputValidator.sanitizedTitle(draft.title) else { throw RepositoryError.invalidTitle }
        let habit = Habit(title: title)
        context.insert(habit)
        apply(draft, to: habit, title: title)
        guard commit() else { throw RepositoryError.saveFailed }
        return habit
    }

    func updateHabit(_ habit: Habit, from draft: HabitDraft) throws {
        guard let title = InputValidator.sanitizedTitle(draft.title) else { throw RepositoryError.invalidTitle }
        apply(draft, to: habit, title: title)
        guard commit() else { throw RepositoryError.saveFailed }
    }

    private func apply(_ draft: HabitDraft, to habit: Habit, title: String) {
        habit.title = title
        habit.symbolName = draft.symbolName
        habit.colorHex = draft.colorHex
        habit.schedule = draft.schedule
        habit.targetCount = min(max(draft.targetCount, 1), 1_000)
        habit.unit = String(draft.unit.prefix(20))
        habit.reminderMinutes = draft.hasReminder ? draft.reminderTime.minutesSinceMidnight : nil
        habit.category = draft.categoryID.flatMap { id in categories().first { $0.id == id } }
    }

    func count(for habit: Habit, on day: Date) -> Int {
        let start = calendar.startOfDay(for: day)
        return habit.entries.filter { $0.day == start }.reduce(0) { $0 + $1.count }
    }

    /// Registra +1 (ou o valor informado) no dia. Para metas quantitativas, acumula.
    func log(_ habit: Habit, on day: Date, amount: Int = 1) {
        let start = calendar.startOfDay(for: day)
        guard start <= calendar.startOfDay(for: now()) else { return } // não registra futuro
        if let entry = habit.entries.first(where: { $0.day == start }) {
            entry.count = max(0, entry.count + amount)
            if entry.count == 0 { context.delete(entry) }
        } else if amount > 0 {
            let entry = HabitEntry(day: start, count: amount)
            context.insert(entry)
            entry.habit = habit
        }
        commit()
    }

    /// Alterna o dia como feito/não feito (hábitos com meta 1, ou completa a meta de uma vez).
    func toggle(_ habit: Habit, on day: Date) {
        let current = count(for: habit, on: day)
        if current >= habit.targetCount {
            log(habit, on: day, amount: -current)
        } else {
            log(habit, on: day, amount: habit.targetCount - current)
        }
    }

    func counts(for habit: Habit) -> [Date: Int] {
        HabitCalculator(calendar: calendar).countsByDay(habit.entries.map { (date: $0.day, count: $0.count) })
    }

    func archive(_ habit: Habit) {
        habit.isArchived = true
        commit()
    }

    func delete(_ habit: Habit) {
        context.delete(habit)
        commit()
    }

    // MARK: Metas

    @discardableResult
    func createGoal(from draft: GoalDraft) throws -> Goal {
        guard let title = InputValidator.sanitizedTitle(draft.title) else { throw RepositoryError.invalidTitle }
        guard draft.endDate >= draft.startDate else { throw RepositoryError.invalidDateRange }
        let goal = Goal(title: title, startDate: draft.startDate, endDate: draft.endDate)
        context.insert(goal)
        apply(draft, to: goal, title: title)
        guard commit() else { throw RepositoryError.saveFailed }
        return goal
    }

    func updateGoal(_ goal: Goal, from draft: GoalDraft) throws {
        guard let title = InputValidator.sanitizedTitle(draft.title) else { throw RepositoryError.invalidTitle }
        guard draft.endDate >= draft.startDate else { throw RepositoryError.invalidDateRange }
        apply(draft, to: goal, title: title)
        guard commit() else { throw RepositoryError.saveFailed }
    }

    private func apply(_ draft: GoalDraft, to goal: Goal, title: String) {
        goal.title = title
        goal.details = InputValidator.sanitizedNotes(draft.details)
        goal.category = draft.categoryID.flatMap { id in categories().first { $0.id == id } }
        goal.startDate = calendar.startOfDay(for: draft.startDate)
        goal.endDate = calendar.startOfDay(for: draft.endDate)
        goal.progressKind = draft.progressKind
        goal.targetValue = draft.progressKind == .milestones ? nil : max(0.0001, draft.targetValue)
        goal.currentValue = max(0, draft.currentValue)
        goal.unit = String(draft.unit.prefix(20))
        goal.linkedHabit = draft.progressKind == .linkedHabit ? draft.linkedHabitID.flatMap { habit(id: $0) } : nil

        // Etapas: mantém estado das que continuam com o mesmo título.
        let titles = draft.milestones.compactMap(InputValidator.sanitizedTitle)
        var existing = goal.sortedMilestones
        for (index, t) in titles.enumerated() {
            if let match = existing.firstIndex(where: { $0.title == t }) {
                existing[match].order = index
                existing.remove(at: match)
            } else {
                let m = GoalMilestone(title: t, order: index)
                context.insert(m)
                m.goal = goal
            }
        }
        existing.forEach { context.delete($0) }
        refreshGoalStatus(goal)
    }

    func toggleMilestone(_ milestone: GoalMilestone) {
        milestone.isDone.toggle()
        if let goal = milestone.goal { refreshGoalStatus(goal) }
        commit()
    }

    func updateProgress(_ goal: Goal, currentValue: Double) {
        goal.currentValue = max(0, currentValue)
        refreshGoalStatus(goal)
        commit()
    }

    func setStatus(_ goal: Goal, _ status: GoalStatus) {
        goal.status = status
        commit()
    }

    /// Marca como concluída quando o progresso atinge 100% (sem reabrir automaticamente metas pausadas/arquivadas).
    private func refreshGoalStatus(_ goal: Goal) {
        let progress = goal.progress(calendar: calendar)
        if progress >= 1, goal.status == .active { goal.status = .completed }
        if progress < 1, goal.status == .completed { goal.status = .active }
    }

    func delete(_ goal: Goal) {
        context.delete(goal)
        commit()
    }

    func goals() -> [Goal] {
        (try? context.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.endDate)]))) ?? []
    }
}
