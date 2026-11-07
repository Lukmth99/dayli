import XCTest
import SwiftData
import DayliCore
@testable import Dayli

@MainActor
final class RepositoryTests: XCTestCase {
    var container: ModelContainer!
    var repo: DayliRepository!
    var calendar: Calendar!
    var fixedNow: Date!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        repo = DayliRepository(context: container.mainContext, calendar: calendar)
        fixedNow = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 10))!
        let now = fixedNow!
        repo.now = { now }
        repo.ensureDefaultCategories()
    }

    private func day(_ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
    }

    // MARK: Tarefas

    func testCreateEditDeleteTask() throws {
        var draft = TaskDraft()
        draft.title = "  Relatório  "
        draft.hasDate = true
        draft.dueDate = day(7, 15)
        draft.hasTime = true
        draft.subtasks = [.init(title: "Rascunho"), .init(title: "   ")]
        let task = try repo.createTask(from: draft)
        XCTAssertEqual(task.title, "Relatório")
        XCTAssertEqual(task.subtasks.count, 1, "Subtarefas vazias são descartadas")

        var edit = TaskDraft(task: task)
        edit.title = "Relatório final"
        edit.priority = .high
        try repo.updateTask(task, from: edit)
        XCTAssertEqual(repo.task(id: task.id)?.title, "Relatório final")
        XCTAssertEqual(repo.task(id: task.id)?.priority, .high)

        repo.delete(task)
        XCTAssertNil(repo.task(id: task.id))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Subtask>()), 0, "Subtarefas são excluídas em cascata")
    }

    func testInvalidTitleIsRejected() {
        var draft = TaskDraft()
        draft.title = "   "
        XCTAssertThrowsError(try repo.createTask(from: draft)) { XCTAssertEqual($0 as? RepositoryError, .invalidTitle) }
        XCTAssertEqual(repo.allTasks().count, 0)
    }

    func testCompleteAndReopen() throws {
        let task = try repo.quickAddTask(title: "Ler", dueDate: day(7))
        repo.complete(task)
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.completedAt, fixedNow)
        repo.reopen(task)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
    }

    func testCompletingRecurringTaskCreatesOnlyNextOccurrence() throws {
        var draft = TaskDraft()
        draft.title = "Beber água"
        draft.hasDate = true
        draft.dueDate = day(7)
        draft.recurrence = RecurrenceRule(frequency: .daily)
        let task = try repo.createTask(from: draft)

        let next = repo.complete(task)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.dueDate, day(8))
        XCTAssertFalse(next!.isCompleted, "A próxima ocorrência nasce pendente")
        XCTAssertNil(task.recurrence, "A ocorrência concluída não gera novas")
        XCTAssertEqual(repo.allTasks().count, 2)
        XCTAssertEqual(repo.allTasks().filter(\.isCompleted).count, 1)
    }

    func testReopeningRecurringTaskRemovesUntouchedGeneratedOccurrence() throws {
        var draft = TaskDraft()
        draft.title = "Revisar"
        draft.hasDate = true
        draft.dueDate = day(7)
        draft.recurrence = RecurrenceRule(frequency: .weekly)
        let task = try repo.createTask(from: draft)
        repo.complete(task)
        XCTAssertEqual(repo.allTasks().count, 2)
        repo.reopen(task)
        XCTAssertEqual(repo.allTasks().count, 1, "Não deve sobrar ocorrência duplicada")
        XCTAssertNotNil(task.recurrence)
    }

    func testRescheduleAndDuplicate() throws {
        let task = try repo.quickAddTask(title: "Ligar para o dentista", dueDate: day(7, 14), hasTime: true)
        repo.rescheduleToTomorrow(task)
        XCTAssertEqual(task.dueDate, day(8, 14))
        XCTAssertEqual(task.rescheduleCount, 1)
        let copy = repo.duplicate(task)
        XCTAssertNotEqual(copy.id, task.id)
        XCTAssertEqual(copy.title, task.title)
        XCTAssertEqual(copy.rescheduleCount, 0)
    }

    func testTasksForTodayIncludeOverdueAndCompletedToday() throws {
        let overdue = try repo.quickAddTask(title: "Atrasada", dueDate: day(5))
        let today = try repo.quickAddTask(title: "Hoje", dueDate: day(7))
        _ = try repo.quickAddTask(title: "Amanhã", dueDate: day(8))
        let done = try repo.quickAddTask(title: "Feita", dueDate: day(6))
        repo.complete(done)
        let ids = Set(repo.tasks(for: day(7)).map(\.id))
        XCTAssertTrue(ids.contains(overdue.id))
        XCTAssertTrue(ids.contains(today.id))
        XCTAssertTrue(ids.contains(done.id), "Concluída hoje aparece no progresso de hoje")
        XCTAssertEqual(ids.count, 3)
    }

    func testDeletingCategoryKeepsTasks() throws {
        let category = try XCTUnwrap(repo.category(for: .work))
        let task = try repo.quickAddTask(title: "Entrega", dueDate: nil, category: category)
        repo.deleteCategory(category)
        XCTAssertNotNil(repo.task(id: task.id))
        XCTAssertNil(repo.task(id: task.id)?.category)
    }

    func testDefaultCategoriesAreIdempotent() {
        repo.ensureDefaultCategories()
        repo.ensureDefaultCategories()
        XCTAssertEqual(repo.categories().count, DefaultCategory.all.count)
    }

    // MARK: Compromissos

    func testEventValidationAndConflicts() throws {
        var draft = EventDraft(start: day(7, 9), calendar: calendar)
        draft.title = "Reunião"
        draft.start = day(7, 9)
        draft.end = day(7, 8)
        XCTAssertThrowsError(try repo.createEvent(from: draft)) { XCTAssertEqual($0 as? RepositoryError, .invalidDateRange) }

        draft.end = day(7, 10)
        let event = try repo.createEvent(from: draft)
        let conflicts = repo.conflicts(start: day(7, 9, 30), end: day(7, 11), excluding: nil, external: [])
        XCTAssertEqual(conflicts.map(\.title), ["Reunião"])
        XCTAssertTrue(repo.conflicts(start: day(7, 9, 30), end: day(7, 11), excluding: event.id, external: []).isEmpty)
    }

    func testRecurringEventOccurrences() throws {
        var draft = EventDraft(start: day(2, 18), calendar: calendar)
        draft.title = "Academia"
        draft.start = day(2, 18)
        draft.end = day(2, 19)
        draft.recurrence = RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6])
        try repo.createEvent(from: draft)
        let week = DateInterval(start: day(2), end: day(9))
        XCTAssertEqual(repo.eventOccurrences(in: week).count, 3)
    }

    // MARK: Hábitos e metas

    func testHabitLoggingAndToggle() throws {
        var draft = HabitDraft()
        draft.title = "Água"
        draft.targetCount = 3
        let habit = try repo.createHabit(from: draft)
        repo.log(habit, on: fixedNow)
        repo.log(habit, on: fixedNow)
        XCTAssertEqual(repo.count(for: habit, on: fixedNow), 2)
        repo.toggle(habit, on: fixedNow)
        XCTAssertEqual(repo.count(for: habit, on: fixedNow), 3)
        repo.toggle(habit, on: fixedNow)
        XCTAssertEqual(repo.count(for: habit, on: fixedNow), 0)
        repo.log(habit, on: day(9))
        XCTAssertEqual(repo.count(for: habit, on: day(9)), 0, "Não registra no futuro")
    }

    func testGoalLinkedToHabitUsesOnlyLinkedEntries() throws {
        var habitDraft = HabitDraft()
        habitDraft.title = "Treinar"
        let habit = try repo.createHabit(from: habitDraft)
        var other = HabitDraft()
        other.title = "Ler"
        let otherHabit = try repo.createHabit(from: other)
        repo.log(habit, on: day(5))
        repo.log(habit, on: day(6))
        repo.log(otherHabit, on: day(6))

        var goalDraft = GoalDraft()
        goalDraft.title = "Treinar 4 vezes"
        goalDraft.startDate = day(1)
        goalDraft.endDate = day(30)
        goalDraft.progressKind = .linkedHabit
        goalDraft.targetValue = 4
        goalDraft.linkedHabitID = habit.id
        let goal = try repo.createGoal(from: goalDraft)
        XCTAssertEqual(goal.progress(calendar: calendar), 0.5, accuracy: 0.0001)
    }

    func testGoalMilestonesCompleteGoal() throws {
        var draft = GoalDraft()
        draft.title = "Organizar viagem"
        draft.startDate = day(1)
        draft.endDate = day(30)
        draft.progressKind = .milestones
        draft.milestones = ["Passagens", "Hotel"]
        let goal = try repo.createGoal(from: draft)
        goal.sortedMilestones.forEach { repo.toggleMilestone($0) }
        XCTAssertEqual(goal.progress(calendar: calendar), 1)
        XCTAssertEqual(goal.status, .completed)
    }

    // MARK: Onboarding e exclusão

    func testOnboardingPersistsAndDeleteAllResets() throws {
        repo.completeOnboarding(name: "Luíza", areas: [.work, .studies], routine: .default)
        XCTAssertTrue(repo.settings().onboardingCompleted)
        XCTAssertEqual(repo.profile().name, "Luíza")
        try repo.deleteAllData()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TaskItem>()), 0)
        XCTAssertFalse(repo.settings().onboardingCompleted, "Configurações recriadas do zero")
    }

    func testLargeVolumeOfTasks() throws {
        for i in 0..<1_000 {
            _ = try repo.quickAddTask(title: "Tarefa \(i)", dueDate: i.isMultiple(of: 2) ? day(7) : nil)
        }
        measure { _ = repo.tasks(for: day(7)) }
        XCTAssertEqual(repo.tasks(for: day(7)).count, 500)
    }
}
