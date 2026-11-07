import XCTest
@testable import DayliCore

final class RecurrenceTests: XCTestCase {
    let cal = TestCalendar.make()

    func testDailyOccurrencesInRange() {
        let anchor = cal.date(2026, 11, 2, 8, 0)
        let rule = RecurrenceRule(frequency: .daily)
        let range = DateInterval(start: cal.date(2026, 11, 5), end: cal.date(2026, 11, 8))
        let result = rule.occurrences(anchor: anchor, in: range, calendar: cal)
        XCTAssertEqual(result, [cal.date(2026, 11, 5, 8), cal.date(2026, 11, 6, 8), cal.date(2026, 11, 7, 8)])
    }

    func testWeeklyWithSpecificWeekdays() {
        // 2 nov 2026 é segunda-feira.
        let anchor = cal.date(2026, 11, 2, 18, 30)
        let rule = RecurrenceRule(frequency: .weekly, weekdays: [2, 4, 6]) // seg, qua, sex
        let range = DateInterval(start: anchor, end: cal.date(2026, 11, 9))
        let result = rule.occurrences(anchor: anchor, in: range, calendar: cal)
        XCTAssertEqual(result, [cal.date(2026, 11, 2, 18, 30), cal.date(2026, 11, 4, 18, 30), cal.date(2026, 11, 6, 18, 30)])
    }

    func testBiweeklyInterval() {
        let anchor = cal.date(2026, 11, 2, 9)
        let rule = RecurrenceRule(frequency: .weekly, interval: 2)
        let range = DateInterval(start: anchor, end: cal.date(2026, 12, 1))
        let result = rule.occurrences(anchor: anchor, in: range, calendar: cal)
        XCTAssertEqual(result, [cal.date(2026, 11, 2, 9), cal.date(2026, 11, 16, 9), cal.date(2026, 11, 30, 9)])
    }

    func testEndDateIsInclusive() {
        let anchor = cal.date(2026, 11, 1, 10)
        let rule = RecurrenceRule(frequency: .daily, endDate: cal.date(2026, 11, 3))
        let range = DateInterval(start: anchor, end: cal.date(2026, 12, 1))
        XCTAssertEqual(rule.occurrences(anchor: anchor, in: range, calendar: cal).count, 3)
    }

    func testMonthlyClampsShortMonths() {
        let anchor = cal.date(2026, 1, 31, 9)
        let rule = RecurrenceRule(frequency: .monthly)
        let next = rule.nextOccurrence(after: anchor, anchor: anchor, calendar: cal)
        XCTAssertEqual(next, cal.date(2026, 2, 28, 9))
    }

    func testRangeFarFromAnchorIsEfficientAndCorrect() {
        let anchor = cal.date(2020, 1, 1, 7)
        let rule = RecurrenceRule(frequency: .daily)
        let range = DateInterval(start: cal.date(2026, 11, 7), end: cal.date(2026, 11, 8))
        XCTAssertEqual(rule.occurrences(anchor: anchor, in: range, calendar: cal), [cal.date(2026, 11, 7, 7)])
    }

    func testDSTPreservesLocalTime() {
        let ny = TestCalendar.make("America/New_York")
        // Horário de verão nos EUA termina em 1º nov 2026.
        let anchor = ny.date(2026, 10, 30, 8)
        let rule = RecurrenceRule(frequency: .daily)
        let result = rule.occurrences(anchor: anchor, in: DateInterval(start: anchor, end: ny.date(2026, 11, 3)), calendar: ny)
        XCTAssertEqual(result.count, 4)
        for date in result { XCTAssertEqual(ny.component(.hour, from: date), 8) }
    }

    // MARK: Tarefas recorrentes

    func testCompletingOccurrenceAdvancesOnlyToNextOne() {
        let anchor = cal.date(2026, 11, 2, 9)
        let rule = RecurrenceRule(frequency: .daily)
        let next = TaskRecurrenceEngine.nextDueDate(rule: rule, anchor: anchor, currentDue: anchor, now: cal.date(2026, 11, 2, 10), calendar: cal)
        XCTAssertEqual(next, cal.date(2026, 11, 3, 9))
    }

    func testVeryOverdueRecurringTaskCatchesUpToToday() {
        let anchor = cal.date(2026, 10, 1, 9)
        let rule = RecurrenceRule(frequency: .daily)
        let next = TaskRecurrenceEngine.nextDueDate(rule: rule, anchor: anchor, currentDue: anchor, now: cal.date(2026, 11, 7, 12), calendar: cal)
        XCTAssertEqual(next, cal.date(2026, 11, 7, 9))
    }

    func testRecurrenceEndsReturnsNil() {
        let anchor = cal.date(2026, 11, 1, 9)
        let rule = RecurrenceRule(frequency: .daily, endDate: cal.date(2026, 11, 1))
        XCTAssertNil(TaskRecurrenceEngine.nextDueDate(rule: rule, anchor: anchor, currentDue: anchor, now: anchor, calendar: cal))
    }

    func testCodableRoundTrip() throws {
        let rule = RecurrenceRule(frequency: .weekly, interval: 2, weekdays: [2, 5], endDate: cal.date(2027, 1, 1))
        let data = try JSONEncoder().encode(rule)
        XCTAssertEqual(try JSONDecoder().decode(RecurrenceRule.self, from: data), rule)
    }
}
