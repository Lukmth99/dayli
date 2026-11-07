import XCTest
@testable import DayliCore

final class HabitTests: XCTestCase {
    let cal = TestCalendar.make()
    lazy var calc = HabitCalculator(calendar: cal)

    private func counts(_ days: [Date]) -> [Date: Int] {
        calc.countsByDay(days.map { (date: $0, count: 1) })
    }

    func testDailyStreakDoesNotBreakOnPendingToday() {
        let today = cal.date(2026, 11, 7, 9)
        let c = counts([cal.date(2026, 11, 6, 8), cal.date(2026, 11, 5, 8), cal.date(2026, 11, 4, 8)])
        let streak = calc.currentStreak(schedule: .daily, target: 1, counts: c, createdAt: cal.date(2026, 10, 1), today: today)
        XCTAssertEqual(streak, HabitStreak(value: 3, unit: .days))
    }

    func testDailyStreakBreaksOnMissedScheduledDay() {
        let today = cal.date(2026, 11, 7, 9)
        let c = counts([cal.date(2026, 11, 7), cal.date(2026, 11, 5)])
        XCTAssertEqual(calc.currentStreak(schedule: .daily, target: 1, counts: c, createdAt: cal.date(2026, 10, 1), today: today).value, 1)
    }

    func testWeekdayHabitIgnoresUnscheduledDays() {
        // Seg (2), Qua (4), Sex (6). Hoje = sábado 7/nov: não programado.
        let schedule = HabitSchedule.weekdays([2, 4, 6])
        let c = counts([cal.date(2026, 11, 6), cal.date(2026, 11, 4), cal.date(2026, 11, 2)])
        let streak = calc.currentStreak(schedule: schedule, target: 1, counts: c, createdAt: cal.date(2026, 11, 1), today: cal.date(2026, 11, 7, 10))
        XCTAssertEqual(streak.value, 3)
    }

    func testQuantitativeTargetRequiresFullCount() {
        let today = cal.date(2026, 11, 7, 20)
        let c = calc.countsByDay([(date: cal.date(2026, 11, 6, 8), count: 5), (date: cal.date(2026, 11, 6, 15), count: 3)])
        XCTAssertEqual(calc.currentStreak(schedule: .daily, target: 8, counts: c, createdAt: cal.date(2026, 11, 1), today: today).value, 1)
        XCTAssertEqual(calc.currentStreak(schedule: .daily, target: 9, counts: c, createdAt: cal.date(2026, 11, 1), today: today).value, 0)
    }

    func testTimesPerWeekStreakCountsWeeks() {
        // Semanas começam no domingo. Semana atual (1–7 nov): 1 registro (ainda em andamento).
        // Semana anterior (25–31 out): 3 registros. Semana de 18–24 out: 3 registros.
        let c = counts([
            cal.date(2026, 11, 2),
            cal.date(2026, 10, 26), cal.date(2026, 10, 28), cal.date(2026, 10, 30),
            cal.date(2026, 10, 19), cal.date(2026, 10, 20), cal.date(2026, 10, 21)
        ])
        let streak = calc.currentStreak(schedule: .timesPerWeek(3), target: 1, counts: c, createdAt: cal.date(2026, 10, 1), today: cal.date(2026, 11, 7))
        XCTAssertEqual(streak, HabitStreak(value: 2, unit: .weeks))
    }

    func testConsistencyDoesNotPenalizeToday() {
        let today = cal.date(2026, 11, 7, 9)
        let c = counts([cal.date(2026, 11, 6), cal.date(2026, 11, 5)])
        let value = calc.consistency(schedule: .daily, target: 1, counts: c, createdAt: cal.date(2026, 11, 5), today: today)
        XCTAssertEqual(value, 1.0, accuracy: 0.0001)
    }

    func testWeekProgressForSpecificDays() {
        let c = counts([cal.date(2026, 11, 2), cal.date(2026, 11, 4)])
        let progress = calc.weekProgress(schedule: .weekdays([2, 4, 6]), target: 1, counts: c, today: cal.date(2026, 11, 5))
        XCTAssertEqual(progress.done, 2)
        XCTAssertEqual(progress.expected, 3)
    }

    func testScheduleCodableRoundTrip() throws {
        for schedule in [HabitSchedule.daily, .weekdays([2, 3]), .timesPerWeek(3)] {
            let data = try JSONEncoder().encode(schedule)
            XCTAssertEqual(try JSONDecoder().decode(HabitSchedule.self, from: data), schedule)
        }
    }
}

final class GoalTests: XCTestCase {
    func testManualProgress() {
        XCTAssertEqual(GoalProgressCalculator.fraction(kind: .manual, currentValue: 10, targetValue: 20, milestonesDone: 0, milestonesTotal: 0, linkedCount: 0), 0.5)
    }

    func testManualProgressClampsAndHandlesMissingTarget() {
        XCTAssertEqual(GoalProgressCalculator.fraction(kind: .manual, currentValue: 30, targetValue: 20, milestonesDone: 0, milestonesTotal: 0, linkedCount: 0), 1)
        XCTAssertEqual(GoalProgressCalculator.fraction(kind: .manual, currentValue: 5, targetValue: nil, milestonesDone: 0, milestonesTotal: 0, linkedCount: 0), 0)
        XCTAssertEqual(GoalProgressCalculator.fraction(kind: .manual, currentValue: -5, targetValue: 10, milestonesDone: 0, milestonesTotal: 0, linkedCount: 0), 0)
    }

    func testMilestoneProgress() {
        XCTAssertEqual(GoalProgressCalculator.fraction(kind: .milestones, currentValue: 0, targetValue: nil, milestonesDone: 1, milestonesTotal: 4, linkedCount: 0), 0.25)
        XCTAssertEqual(GoalProgressCalculator.fraction(kind: .milestones, currentValue: 0, targetValue: nil, milestonesDone: 0, milestonesTotal: 0, linkedCount: 0), 0)
    }

    func testLinkedHabitProgressIgnoresManualValue() {
        // "Treinar 12 vezes": 6 registros vinculados → 50%, independentemente do valor manual.
        XCTAssertEqual(GoalProgressCalculator.fraction(kind: .linkedHabit, currentValue: 99, targetValue: 12, milestonesDone: 0, milestonesTotal: 0, linkedCount: 6), 0.5)
    }
}

final class TaskRulesTests: XCTestCase {
    let cal = TestCalendar.make()

    func testFilters() {
        let now = cal.date(2026, 11, 7, 10)
        XCTAssertTrue(TaskFilter.today.matches(dueDate: cal.date(2026, 11, 7, 18), isCompleted: false, now: now, calendar: cal))
        XCTAssertTrue(TaskFilter.today.matches(dueDate: cal.date(2026, 11, 3), isCompleted: false, now: now, calendar: cal))
        XCTAssertFalse(TaskFilter.today.matches(dueDate: cal.date(2026, 11, 7), isCompleted: true, now: now, calendar: cal))
        XCTAssertTrue(TaskFilter.upcoming.matches(dueDate: cal.date(2026, 11, 8), isCompleted: false, now: now, calendar: cal))
        XCTAssertFalse(TaskFilter.upcoming.matches(dueDate: cal.date(2026, 11, 11), isCompleted: false, now: now, calendar: cal))
        XCTAssertTrue(TaskFilter.thisWeek.matches(dueDate: cal.date(2026, 11, 13), isCompleted: false, now: now, calendar: cal))
        XCTAssertTrue(TaskFilter.later.matches(dueDate: cal.date(2026, 11, 14), isCompleted: false, now: now, calendar: cal))
        XCTAssertTrue(TaskFilter.noDate.matches(dueDate: nil, isCompleted: false, now: now, calendar: cal))
        XCTAssertTrue(TaskFilter.completed.matches(dueDate: nil, isCompleted: true, now: now, calendar: cal))
    }

    func testOverdueRules() {
        let now = cal.date(2026, 11, 7, 10)
        XCTAssertFalse(TaskTiming.isOverdue(dueDate: cal.date(2026, 11, 7), hasTime: false, isCompleted: false, now: now, calendar: cal))
        XCTAssertTrue(TaskTiming.isOverdue(dueDate: cal.date(2026, 11, 7, 9), hasTime: true, isCompleted: false, now: now, calendar: cal))
        XCTAssertTrue(TaskTiming.isOverdue(dueDate: cal.date(2026, 11, 6), hasTime: false, isCompleted: false, now: now, calendar: cal))
        XCTAssertFalse(TaskTiming.isOverdue(dueDate: cal.date(2026, 11, 6), hasTime: false, isCompleted: true, now: now, calendar: cal))
    }

    func testGentleLabels() {
        let now = cal.date(2026, 11, 7, 10)
        XCTAssertEqual(TaskTiming.gentleOverdueLabel(dueDate: cal.date(2026, 11, 6), now: now, calendar: cal), "Ficou de ontem")
        XCTAssertEqual(TaskTiming.gentleOverdueLabel(dueDate: cal.date(2026, 11, 3), now: now, calendar: cal), "Aguardando há 4 dias")
    }

    func testRescheduleToTomorrowKeepsTime() {
        let now = cal.date(2026, 11, 7, 10)
        XCTAssertEqual(TaskTiming.rescheduledToTomorrow(dueDate: cal.date(2026, 11, 7, 14, 30), hasTime: true, now: now, calendar: cal), cal.date(2026, 11, 8, 14, 30))
        XCTAssertEqual(TaskTiming.rescheduledToTomorrow(dueDate: nil, hasTime: false, now: now, calendar: cal), cal.date(2026, 11, 8))
    }

    func testInputSanitization() {
        XCTAssertNil(InputValidator.sanitizedTitle("   \n\t "))
        XCTAssertEqual(InputValidator.sanitizedTitle("  Ler\u{0007} livro "), "Ler livro")
        XCTAssertEqual(InputValidator.sanitizedTitle(String(repeating: "a", count: 500))?.count, InputValidator.maxTitleLength)
    }

    func testGreeting() {
        XCTAssertEqual(Greeting.salutation(for: cal.date(2026, 11, 7, 7), calendar: cal), "Bom dia")
        XCTAssertEqual(Greeting.salutation(for: cal.date(2026, 11, 7, 13), calendar: cal), "Boa tarde")
        XCTAssertEqual(Greeting.salutation(for: cal.date(2026, 11, 7, 22), calendar: cal), "Boa noite")
        XCTAssertEqual(Greeting.salutation(for: cal.date(2026, 11, 7, 2), calendar: cal), "Boa noite")
    }
}
