import XCTest
@testable import DayliCore

final class SchedulingTests: XCTestCase {
    let cal = TestCalendar.make()

    // MARK: Conflitos

    func testOverlapIsStrict() {
        let a = DateInterval(start: cal.date(2026, 11, 7, 9), end: cal.date(2026, 11, 7, 10))
        let touching = DateInterval(start: cal.date(2026, 11, 7, 10), end: cal.date(2026, 11, 7, 11))
        let overlapping = DateInterval(start: cal.date(2026, 11, 7, 9, 30), end: cal.date(2026, 11, 7, 11))
        XCTAssertFalse(ConflictDetector.overlaps(a, touching))
        XCTAssertTrue(ConflictDetector.overlaps(a, overlapping))
    }

    func testAllConflictsFindsPairs() {
        let items = [
            BusyInterval(id: "a", title: "A", start: cal.date(2026, 11, 7, 9), end: cal.date(2026, 11, 7, 11))!,
            BusyInterval(id: "b", title: "B", start: cal.date(2026, 11, 7, 10), end: cal.date(2026, 11, 7, 12))!,
            BusyInterval(id: "c", title: "C", start: cal.date(2026, 11, 7, 12), end: cal.date(2026, 11, 7, 13))!
        ]
        let pairs = ConflictDetector.allConflicts(items)
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.first.id, "a")
        XCTAssertEqual(pairs.first?.second.id, "b")
    }

    func testBusyIntervalRejectsInvertedRange() {
        XCTAssertNil(BusyInterval(id: "x", title: "X", start: cal.date(2026, 11, 7, 10), end: cal.date(2026, 11, 7, 9)))
    }

    // MARK: Janelas livres

    func testFreeSlotsWithBuffer() {
        let window = DateInterval(start: cal.date(2026, 11, 7, 8), end: cal.date(2026, 11, 7, 12))
        let busy = [DateInterval(start: cal.date(2026, 11, 7, 9), end: cal.date(2026, 11, 7, 10))]
        let slots = FreeSlotFinder.freeSlots(in: window, busy: busy, buffer: 600)
        XCTAssertEqual(slots, [
            DateInterval(start: cal.date(2026, 11, 7, 8), end: cal.date(2026, 11, 7, 8, 50)),
            DateInterval(start: cal.date(2026, 11, 7, 10, 10), end: cal.date(2026, 11, 7, 12))
        ])
    }

    func testFreeSlotsMergesOverlappingBusy() {
        let window = DateInterval(start: cal.date(2026, 11, 7, 8), end: cal.date(2026, 11, 7, 12))
        let busy = [
            DateInterval(start: cal.date(2026, 11, 7, 9), end: cal.date(2026, 11, 7, 10, 30)),
            DateInterval(start: cal.date(2026, 11, 7, 10), end: cal.date(2026, 11, 7, 11))
        ]
        let slots = FreeSlotFinder.freeSlots(in: window, busy: busy)
        XCTAssertEqual(slots.count, 2)
        XCTAssertEqual(slots[1].start, cal.date(2026, 11, 7, 11))
    }

    // MARK: Planejador

    private func task(_ title: String, _ priority: Priority = .medium, due: Date? = nil, minutes: Int = 30, area: LifeArea? = nil) -> PlannableTask {
        PlannableTask(id: UUID(), title: title, priority: priority, dueDate: due, estimatedMinutes: minutes, area: area)
    }

    func testPlannerNeverSchedulesDuringBusyPeriods() {
        let day = cal.date(2026, 11, 7) // sábado (não é dia de trabalho por padrão)
        let busy = [BusyInterval(id: "e", title: "Almoço", start: cal.date(2026, 11, 7, 7), end: cal.date(2026, 11, 7, 20))!]
        let planner = DayPlanner(calendar: cal)
        let plan = planner.plan(day: day, tasks: [task("Ler", minutes: 60)], busy: busy, routine: .default, now: cal.date(2026, 11, 7, 6))
        XCTAssertEqual(plan.suggestions.count, 1)
        let s = plan.suggestions[0]
        XCTAssertGreaterThanOrEqual(s.start, cal.date(2026, 11, 7, 20, 10))
        XCTAssertLessThanOrEqual(s.end, cal.date(2026, 11, 7, 23))
        XCTAssertFalse(ConflictDetector.overlaps(DateInterval(start: s.start, end: s.end), busy[0].interval))
    }

    func testPlannerPrioritizesOverdueThenHighPriority() {
        let day = cal.date(2026, 11, 7)
        let overdue = task("Atrasada", .low, due: cal.date(2026, 11, 5))
        let high = task("Alta", .high)
        let low = task("Baixa", .low)
        let order = DayPlanner(calendar: cal).sortForPlanning([low, high, overdue], day: day).map(\.title)
        XCTAssertEqual(order, ["Atrasada", "Alta", "Baixa"])
    }

    func testPlannerPutsWorkTasksInWorkHoursOnWorkdays() {
        let day = cal.date(2026, 11, 9) // segunda-feira
        let plan = DayPlanner(calendar: cal).plan(day: day, tasks: [task("Relatório", .high, minutes: 60, area: .work), task("Academia", minutes: 60, area: .fitness)],
                                                  busy: [], routine: .default, now: cal.date(2026, 11, 9, 6))
        let work = plan.suggestions.first { $0.title == "Relatório" }!
        let gym = plan.suggestions.first { $0.title == "Academia" }!
        XCTAssertGreaterThanOrEqual(work.start, cal.date(2026, 11, 9, 9))
        XCTAssertLessThanOrEqual(work.end, cal.date(2026, 11, 9, 18))
        let workBlock = DateInterval(start: cal.date(2026, 11, 9, 9), end: cal.date(2026, 11, 9, 18))
        XCTAssertFalse(ConflictDetector.overlaps(DateInterval(start: gym.start, end: gym.end), workBlock))
    }

    func testPlannerDoesNotSuggestPastTimes() {
        let now = cal.date(2026, 11, 7, 15, 2)
        let plan = DayPlanner(calendar: cal).plan(day: now, tasks: [task("Algo")], busy: [], routine: .default, now: now)
        XCTAssertEqual(plan.suggestions.first?.start, cal.date(2026, 11, 7, 15, 5))
    }

    func testPlannerRespectsPersonalLoadLimit() {
        var routine = RoutineSettings.default
        routine.maxPersonalFocusMinutes = 60
        let plan = DayPlanner(calendar: cal).plan(day: cal.date(2026, 11, 7), tasks: [task("A", minutes: 45), task("B", minutes: 45)],
                                                  busy: [], routine: routine, now: cal.date(2026, 11, 7, 6))
        XCTAssertEqual(plan.suggestions.count, 1)
        XCTAssertEqual(plan.unplanned.count, 1)
    }

    func testPlannerReportsUnplannableWhenDayIsFull() {
        let busy = [BusyInterval(id: "x", title: "Viagem", start: cal.date(2026, 11, 7, 0), end: cal.date(2026, 11, 8, 2))!]
        let plan = DayPlanner(calendar: cal).plan(day: cal.date(2026, 11, 7), tasks: [task("A")], busy: busy, routine: .default, now: cal.date(2026, 11, 7, 6))
        XCTAssertTrue(plan.suggestions.isEmpty)
        XCTAssertEqual(plan.unplanned.count, 1)
    }

    func testPlannerHandlesSleepAfterMidnight() {
        var routine = RoutineSettings.default
        routine.wake = TimeOfDay(hour: 22)
        routine.sleep = TimeOfDay(hour: 1)
        let plan = DayPlanner(calendar: cal).plan(day: cal.date(2026, 11, 7), tasks: [task("Noturna", minutes: 120)], busy: [], routine: routine, now: cal.date(2026, 11, 7, 6))
        XCTAssertEqual(plan.suggestions.first?.start, cal.date(2026, 11, 7, 22))
        XCTAssertEqual(plan.suggestions.first?.end, cal.date(2026, 11, 8, 0))
    }

    func testPlannerAcrossDSTDayKeepsLocalWakeTime() {
        let ny = TestCalendar.make("America/New_York")
        let day = ny.date(2026, 11, 1) // fim do horário de verão
        let plan = DayPlanner(calendar: ny).plan(day: day, tasks: [task("A")], busy: [], routine: .default, now: ny.date(2026, 11, 1, 0))
        XCTAssertEqual(ny.component(.hour, from: plan.suggestions[0].start), 7)
    }

    // MARK: Linha do tempo e progresso

    func testTimelineDedupesMirroredExternalEvents() {
        let start = cal.date(2026, 11, 7, 10)
        let dayliEvent = TimelineEntry(id: "event:1", kind: .event, sourceID: "1", title: "Reunião", start: start, linkedExternalIdentifier: "EK-1")
        let mirror = TimelineEntry(id: "ext:EK-1", kind: .externalEvent, sourceID: "EK-1", title: "Reunião", start: start)
        let other = TimelineEntry(id: "ext:EK-2", kind: .externalEvent, sourceID: "EK-2", title: "Dentista", start: cal.date(2026, 11, 7, 15))
        let result = TimelineBuilder.build(tasks: [], events: [dayliEvent], external: [mirror, other, other])
        XCTAssertEqual(result.map(\.id), ["event:1", "ext:EK-2"])
    }

    func testProgressIgnoresCalendarEvents() {
        let now = cal.date(2026, 11, 7, 10)
        let entries = [
            TimelineEntry(id: "t1", kind: .task, sourceID: "1", title: "A", start: now, isCompleted: true),
            TimelineEntry(id: "t2", kind: .task, sourceID: "2", title: "B", start: now),
            TimelineEntry(id: "e1", kind: .event, sourceID: "3", title: "Evento", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
        ]
        let progress = DailyProgress.from(entries: entries)
        XCTAssertEqual(progress.total, 2)
        XCTAssertEqual(progress.completed, 1)
        XCTAssertEqual(progress.percent, 50)
    }

    func testEmptyProgressIsZeroNotNaN() {
        XCTAssertEqual(DailyProgress(total: 0, completed: 0).fraction, 0)
    }

    func testNextEventSkipsFinishedAndTasks() {
        let now = cal.date(2026, 11, 7, 12)
        let entries = [
            TimelineEntry(id: "past", kind: .event, sourceID: "p", title: "Passado", start: cal.date(2026, 11, 7, 9), end: cal.date(2026, 11, 7, 10)),
            TimelineEntry(id: "task", kind: .task, sourceID: "t", title: "Tarefa", start: cal.date(2026, 11, 7, 13)),
            TimelineEntry(id: "next", kind: .externalEvent, sourceID: "n", title: "Próximo", start: cal.date(2026, 11, 7, 14), end: cal.date(2026, 11, 7, 15))
        ]
        XCTAssertEqual(TimelineBuilder.nextEvent(in: entries, now: now)?.id, "next")
    }

    // MARK: Volume

    func testPlannerWithLargeVolumeStaysValid() {
        let tasks = (0..<500).map { task("T\($0)", Priority(rawValue: $0 % 3)!, minutes: 15 + ($0 % 4) * 15) }
        let busy = (0..<200).compactMap { i -> BusyInterval? in
            // Blocos de 2 min a cada 45 min: deixa janelas de ~23 min entre eles (com respiro).
            let start = cal.date(2026, 11, 7, 7).addingTimeInterval(TimeInterval(i * 2_700))
            return BusyInterval(id: "b\(i)", title: "B", start: start, end: start.addingTimeInterval(120))
        }
        let plan = DayPlanner(calendar: cal).plan(day: cal.date(2026, 11, 7), tasks: tasks, busy: busy, routine: .default, now: cal.date(2026, 11, 7, 6))
        XCTAssertEqual(plan.suggestions.count + plan.unplanned.count, 500)
        for s in plan.suggestions {
            XCTAssertTrue(ConflictDetector.conflicts(for: DateInterval(start: s.start, end: s.end), in: busy).isEmpty)
        }
        // Sugestões não se sobrepõem entre si.
        let sorted = plan.suggestions.sorted { $0.start < $1.start }
        for (a, b) in zip(sorted, sorted.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start) }
    }
}
