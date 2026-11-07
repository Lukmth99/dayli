import XCTest
@testable import DayliCore

final class AIProposalTests: XCTestCase {
    let cal = TestCalendar.make()

    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testParsesValidProposal() throws {
        let json = """
        {"version":1,"message":"Sugestão pronta","actions":[
          {"type":"createTask","title":"Estudar","start":"2026-11-07T20:00:00-03:00","durationMinutes":120,"priority":2}
        ]}
        """
        let proposal = try AIResponseParser.parse(data(json))
        XCTAssertEqual(proposal.actions.count, 1)
        XCTAssertEqual(proposal.actions[0].priority, .high)
        XCTAssertEqual(proposal.actions[0].durationMinutes, 120)
    }

    func testRejectsUnknownActionType() {
        let json = #"{"version":1,"message":"x","actions":[{"type":"deleteEverything"}]}"#
        XCTAssertThrowsError(try AIResponseParser.parse(data(json))) { XCTAssertEqual($0 as? AIResponseError, .malformed) }
    }

    func testRejectsMalformedJSONAndWrongTypes() {
        XCTAssertThrowsError(try AIResponseParser.parse(data("não é json")))
        XCTAssertThrowsError(try AIResponseParser.parse(data(#"{"version":1,"message":"x","actions":[{"type":"createTask","durationMinutes":"duas horas"}]}"#)))
        XCTAssertThrowsError(try AIResponseParser.parse(data(#"{"version":1,"message":"x","actions":[{"type":"createTask","start":"amanhã"}]}"#)))
    }

    func testRejectsUnsupportedVersionAndTooManyActions() {
        XCTAssertThrowsError(try AIResponseParser.parse(data(#"{"version":2,"message":"x","actions":[]}"#))) {
            XCTAssertEqual($0 as? AIResponseError, .unsupportedVersion(2))
        }
        let many = Array(repeating: #"{"type":"createTask","title":"a"}"#, count: AIProposal.maxActions + 1).joined(separator: ",")
        XCTAssertThrowsError(try AIResponseParser.parse(data(#"{"version":1,"message":"x","actions":[\#(many)]}"#)))
    }

    func testRejectsOversizedPayload() {
        let huge = String(repeating: "a", count: AIResponseParser.maxPayloadBytes + 1)
        XCTAssertThrowsError(try AIResponseParser.parse(data(huge)))
    }

    func testValidatorRejectsUnknownTasksAndPastTimes() {
        let now = cal.date(2026, 11, 7, 10)
        let known = UUID()
        let proposal = AIProposal(message: "ok", actions: [
            AIAction(type: .rescheduleTask, taskID: UUID(), start: cal.date(2026, 11, 7, 15), durationMinutes: 30),
            AIAction(type: .rescheduleTask, taskID: known, start: cal.date(2026, 11, 6, 15), durationMinutes: 30),
            AIAction(type: .createTask, title: "   "),
            AIAction(type: .createEvent, title: "Sem horário"),
            AIAction(type: .rescheduleTask, taskID: known, start: cal.date(2026, 11, 7, 15), durationMinutes: 30),
            AIAction(type: .createTask, title: "Longe", start: cal.date(2027, 6, 1, 9), durationMinutes: 30),
            AIAction(type: .createTask, title: "Duração", start: cal.date(2026, 11, 8, 9), durationMinutes: 2_000)
        ])
        let ctx = AIValidationContext(knownTaskIDs: [known], busy: [], now: now, calendar: cal)
        let result = AIProposalValidator.validate(proposal, context: ctx)
        XCTAssertEqual(result.valid.count, 1)
        XCTAssertEqual(result.rejected.map(\.reason), [.unknownTask, .startInPast, .missingTitle, .missingStart, .beyondHorizon, .invalidDuration])
    }

    func testValidatorWarnsAboutConflictsIncludingWithinProposal() {
        let now = cal.date(2026, 11, 7, 8)
        let busy = [BusyInterval(id: "event:1", title: "Reunião", start: cal.date(2026, 11, 7, 10), end: cal.date(2026, 11, 7, 11))!]
        let proposal = AIProposal(message: "ok", actions: [
            AIAction(type: .createTask, title: "A", start: cal.date(2026, 11, 7, 10, 30), durationMinutes: 30),
            AIAction(type: .createTask, title: "B", start: cal.date(2026, 11, 7, 12), durationMinutes: 60),
            AIAction(type: .createTask, title: "C", start: cal.date(2026, 11, 7, 12, 30), durationMinutes: 30)
        ])
        let result = AIProposalValidator.validate(proposal, context: AIValidationContext(knownTaskIDs: [], busy: busy, now: now, calendar: cal))
        XCTAssertEqual(result.valid.count, 3)
        XCTAssertFalse(result.valid[0].warnings.isEmpty)
        XCTAssertTrue(result.valid[1].warnings.isEmpty)
        XCTAssertFalse(result.valid[2].warnings.isEmpty)
    }

    func testValidatorSanitizesTitles() {
        let now = cal.date(2026, 11, 7, 8)
        let proposal = AIProposal(message: "ok", actions: [AIAction(type: .createTask, title: "  Ler\u{0000} ")])
        let result = AIProposalValidator.validate(proposal, context: AIValidationContext(knownTaskIDs: [], busy: [], now: now, calendar: cal))
        XCTAssertEqual(result.valid.first?.action.title, "Ler")
    }

    func testEncodeDecodeRoundTrip() throws {
        let proposal = AIProposal(message: "m", actions: [AIAction(type: .setTaskPriority, taskID: UUID(), priority: .low)])
        let data = try AIResponseParser.makeEncoder().encode(proposal)
        XCTAssertEqual(try AIResponseParser.parse(data), proposal)
    }
}

final class PrivacyTests: XCTestCase {
    func testRedactsSensitivePatterns() {
        let text = "Ligar para 11 91234-5678, CPF 123.456.789-09, e-mail ana@banco.com.br, conta 12345-6, cartão 4111 1111 1111 1111, contrato 9876543"
        let redacted = SensitiveDataRedactor.redact(text)
        XCTAssertFalse(redacted.contains("91234"))
        XCTAssertFalse(redacted.contains("123.456.789-09"))
        XCTAssertFalse(redacted.contains("ana@banco.com.br"))
        XCTAssertFalse(redacted.contains("12345-6"))
        XCTAssertFalse(redacted.contains("4111"))
        XCTAssertFalse(redacted.contains("9876543"))
        XCTAssertTrue(redacted.contains("Ligar para"))
    }

    func testKeepsOrdinaryText() {
        let text = "Estudar 2 horas às 20:00 no dia 07/11"
        XCTAssertEqual(SensitiveDataRedactor.redact(text), text)
        XCTAssertFalse(SensitiveDataRedactor.containsSensitiveData(text))
    }

    func testContextHidesTitlesByDefault() {
        let cal = TestCalendar.make()
        let task = PlannableTask(id: UUID(), title: "Conciliar conta 123456 do cliente", priority: .high, dueDate: nil, estimatedMinutes: 30, area: .work)
        let busy = [BusyInterval(id: "b", title: "Reunião com cliente X", start: cal.date(2026, 11, 7, 9), end: cal.date(2026, 11, 7, 10))!]
        let payload = AIContextBuilder.build(message: "organize meu dia", tasks: [task], busy: busy, routine: .default,
                                             now: cal.date(2026, 11, 7, 8), timeZone: cal.timeZone, options: AIContextOptions())
        XCTAssertEqual(payload.tasks.first?.title, "Tarefa de Trabalho")
        XCTAssertEqual(payload.busy.first?.label, "Ocupado")
    }

    func testContextRedactsWhenSharingTitles() {
        let cal = TestCalendar.make()
        let task = PlannableTask(id: UUID(), title: "Conciliar conta 123456", priority: .high, dueDate: nil, estimatedMinutes: 30, area: .work)
        let payload = AIContextBuilder.build(message: "meu cpf é 123.456.789-09", tasks: [task], busy: [], routine: .default,
                                             now: cal.date(2026, 11, 7, 8), timeZone: cal.timeZone, options: AIContextOptions(shareTitles: true))
        XCTAssertFalse(payload.tasks[0].title.contains("123456"))
        XCTAssertFalse(payload.userMessage.contains("123.456.789-09"))
    }
}

final class NotificationPlannerTests: XCTestCase {
    let cal = TestCalendar.make()

    func testQuietHoursAcrossMidnight() {
        let quiet = QuietHours(start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
        XCTAssertTrue(quiet.contains(cal.date(2026, 11, 7, 23), calendar: cal))
        XCTAssertTrue(quiet.contains(cal.date(2026, 11, 7, 6, 59), calendar: cal))
        XCTAssertFalse(quiet.contains(cal.date(2026, 11, 7, 7), calendar: cal))
        XCTAssertEqual(quiet.endOfQuiet(after: cal.date(2026, 11, 7, 23), calendar: cal), cal.date(2026, 11, 8, 7))
    }

    func testFinalizeDedupesShiftsAndLimits() {
        let now = cal.date(2026, 11, 7, 12)
        let quiet = QuietHours(start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
        var items = [
            PlannedNotification(id: "task.a", kind: .task, title: "A", body: "", fireDate: cal.date(2026, 11, 7, 23)),
            PlannedNotification(id: "task.a", kind: .task, title: "A dup", body: "", fireDate: cal.date(2026, 11, 7, 15)),
            PlannedNotification(id: "past", kind: .task, title: "P", body: "", fireDate: cal.date(2026, 11, 7, 9)),
            PlannedNotification(id: "event.b", kind: .event, title: "B", body: "", fireDate: cal.date(2026, 11, 7, 23), bypassesQuietHours: true)
        ]
        for i in 0..<100 {
            items.append(PlannedNotification(id: "bulk.\(i)", kind: .task, title: "", body: "", fireDate: cal.date(2026, 11, 20).addingTimeInterval(TimeInterval(i * 60))))
        }
        let result = NotificationPlanner.finalize(items, quietHours: quiet, now: now, calendar: cal)
        XCTAssertEqual(result.count, NotificationPlanner.systemLimit)
        XCTAssertEqual(result[0].id, "event.b")
        XCTAssertEqual(result[0].fireDate, cal.date(2026, 11, 7, 23))
        XCTAssertEqual(result[1].id, "task.a")
        XCTAssertEqual(result[1].fireDate, cal.date(2026, 11, 8, 7))
        XCTAssertFalse(result.contains { $0.id == "past" })
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testNextEventAndPrivacy() throws {
        let cal = TestCalendar.make()
        let snapshot = WidgetSnapshot(generatedAt: cal.date(2026, 11, 7, 8), day: cal.date(2026, 11, 7), events: [
            .init(id: "1", title: "Banco", start: cal.date(2026, 11, 7, 9), end: cal.date(2026, 11, 7, 10), colorHex: nil, isTask: false, isCompleted: false, priority: nil),
            .init(id: "2", title: "Academia", start: cal.date(2026, 11, 7, 18), end: cal.date(2026, 11, 7, 19), colorHex: nil, isTask: false, isCompleted: false, priority: nil)
        ], priorityTasks: [], totalTasks: 4, completedTasks: 1, hideDetails: true)
        XCTAssertEqual(snapshot.nextEvent(at: cal.date(2026, 11, 7, 12))?.id, "2")
        XCTAssertEqual(snapshot.displayTitle(for: snapshot.events[0]), "Compromisso")
        XCTAssertEqual(snapshot.transitionDates(after: cal.date(2026, 11, 7, 12)), [cal.date(2026, 11, 7, 18), cal.date(2026, 11, 7, 19)])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try WidgetSnapshotStore.write(snapshot, to: dir)
        XCTAssertEqual(WidgetSnapshotStore.read(from: dir), snapshot)
    }
}
