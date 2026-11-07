import XCTest
import SwiftData
import DayliCore
@testable import Dayli

/// Serviço falso que devolve uma resposta fixa (inclusive inválida).
private struct StubAIService: AIService {
    var kind: AIServiceKind { .remote }
    let response: Result<Data, Error>
    func propose(for payload: AIContextPayload) async throws -> AIProposal {
        try AIResponseParser.parse(try response.get())
    }
}

@MainActor
final class AIFlowTests: XCTestCase {
    // O contêiner precisa ficar retido durante o teste: o ModelContext não o mantém vivo.
    var container: ModelContainer!
    var repo: DayliRepository!
    var calendar: Calendar!

    override func setUp() async throws {
        container = try PersistenceController.makeContainer(inMemory: true)
        calendar = Calendar.dayli
        repo = DayliRepository(context: container.mainContext, calendar: calendar)
        repo.ensureDefaultCategories()
    }

    func testInvalidModelResponseNeverReachesData() async throws {
        let stub = StubAIService(response: .success(Data(#"{"version":1,"message":"x","actions":[{"type":"dropDatabase"}]}"#.utf8)))
        let payload = AIContextBuilder.build(message: "oi", tasks: [], busy: [], routine: .default, now: .now, timeZone: .current, options: .init())
        do {
            _ = try await stub.propose(for: payload)
            XCTFail("Deveria rejeitar")
        } catch {
            XCTAssertEqual(error as? AIResponseError, .malformed)
        }
        XCTAssertEqual(repo.allTasks().count, 0)
    }

    func testOnlyConfirmedActionsAreApplied() throws {
        let task = try repo.quickAddTask(title: "Relatório", dueDate: calendar.startOfDay(for: .now))
        let start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!.addingTimeInterval(15 * 3600)
        let proposal = AIProposal(message: "ok", actions: [
            AIAction(type: .createTask, title: "Estudar", start: start, durationMinutes: 60),
            AIAction(type: .rescheduleTask, taskID: task.id, start: start.addingTimeInterval(7200), durationMinutes: 30)
        ])
        let validation = AIProposalValidator.validate(proposal, context: AIValidationContext(
            knownTaskIDs: [task.id], busy: [], now: .now, calendar: calendar))
        XCTAssertEqual(validation.valid.count, 2)

        // Antes da confirmação nada mudou.
        XCTAssertEqual(repo.allTasks().count, 1)
        XCTAssertNotEqual(task.dueDate, start.addingTimeInterval(7200))

        // Usuária aprova só a segunda ação.
        let record = AIProposalRecord(proposalJSON: try AIResponseParser.makeEncoder().encode(proposal))
        repo.context.insert(record)
        let outcome = AIProposalExecutor(repository: repo).apply([validation.valid[1]], record: record)
        XCTAssertEqual(outcome.applied.count, 1)
        XCTAssertEqual(repo.allTasks().count, 1, "A criação não aprovada não foi executada")
        XCTAssertEqual(task.dueDate, start.addingTimeInterval(7200))
        XCTAssertEqual(record.status, .applied)
    }

    func testExecutorIgnoresCompletedOrMissingTasks() throws {
        let task = try repo.quickAddTask(title: "Feita", dueDate: .now)
        repo.complete(task)
        let action = ValidatedAIAction(action: AIAction(type: .rescheduleTask, taskID: task.id, start: .now.addingTimeInterval(3600), durationMinutes: 30), warnings: [])
        let missing = ValidatedAIAction(action: AIAction(type: .rescheduleTask, taskID: UUID(), start: .now.addingTimeInterval(3600), durationMinutes: 30), warnings: [])
        let outcome = AIProposalExecutor(repository: repo).apply([action, missing], record: nil)
        XCTAssertEqual(outcome.applied.count, 0)
        XCTAssertEqual(outcome.failed.count, 2)
    }

    func testLocalAssistantProposesWithoutChangingData() async throws {
        _ = try repo.quickAddTask(title: "Relatório", dueDate: calendar.startOfDay(for: .now), priority: .high)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let payload = AIContextBuilder.build(message: "Organize meu dia de amanhã", tasks: repo.pendingTasks().map(\.plannable),
                                             busy: [], routine: .default, now: calendar.startOfDay(for: .now).addingTimeInterval(6 * 3600),
                                             timeZone: calendar.timeZone, options: .init(shareTitles: true, redactSensitive: false))
        let proposal = try await LocalRulesAIService().propose(for: payload)
        XCTAssertFalse(proposal.actions.isEmpty)
        XCTAssertTrue(proposal.actions.allSatisfy { $0.type == .rescheduleTask })
        XCTAssertTrue(proposal.actions.allSatisfy { calendar.isDate($0.start!, inSameDayAs: tomorrow) })
        XCTAssertNil(repo.pendingTasks().first?.endDate, "Nada foi alterado sem confirmação")
    }

    func testRemoteServiceRequiresHTTPS() {
        XCTAssertThrowsError(try RemoteAIService(baseURL: URL(string: "http://exemplo.com")!, sessionToken: nil)) {
            XCTAssertEqual($0 as? AIServiceError, .insecureURL)
        }
    }

    func testCalendarAccessDeniedYieldsNoExternalEvents() {
        let service = CalendarService()
        service.isEnabled = true
        // Em simulador sem permissão concedida, nunca deve lançar nem retornar eventos.
        if !service.accessState.canRead {
            XCTAssertTrue(service.events(in: DateInterval(start: .now, duration: 86_400)).isEmpty)
        }
        service.isEnabled = false
        XCTAssertTrue(service.events(in: DateInterval(start: .now, duration: 86_400)).isEmpty)
    }
}
