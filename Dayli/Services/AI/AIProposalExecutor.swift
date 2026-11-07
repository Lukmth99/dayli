import Foundation
import DayliCore

/// Executa SOMENTE ações validadas e aprovadas pela usuária.
/// Cada ação é mapeada para uma operação conhecida do repositório — nunca
/// executamos comandos arbitrários vindos do modelo.
@MainActor
struct AIProposalExecutor {
    let repository: DayliRepository

    struct Outcome: Equatable {
        var applied: [UUID] = []
        var failed: [UUID] = []

        var summary: String {
            switch (applied.count, failed.count) {
            case (0, 0): return "Nenhuma alteração foi feita."
            case (let a, 0): return a == 1 ? "1 alteração aplicada." : "\(a) alterações aplicadas."
            case (0, let f): return f == 1 ? "Não foi possível aplicar a alteração." : "Não foi possível aplicar \(f) alterações."
            case (let a, let f): return "\(a) aplicada(s), \(f) não pôde(puderam) ser aplicada(s)."
            }
        }
    }

    func apply(_ actions: [ValidatedAIAction], record: AIProposalRecord?) -> Outcome {
        var outcome = Outcome()
        for validated in actions {
            if perform(validated.action) {
                outcome.applied.append(validated.id)
            } else {
                outcome.failed.append(validated.id)
            }
        }
        if let record {
            record.appliedActionIDs = outcome.applied
            record.resultSummary = outcome.summary
            record.status = outcome.failed.isEmpty ? (outcome.applied.isEmpty ? .rejected : .applied) : (outcome.applied.isEmpty ? .failed : .partiallyApplied)
            repository.commit()
        }
        return outcome
    }

    private func perform(_ action: AIAction) -> Bool {
        let category = action.categoryName.flatMap { repository.category(named: $0) }
        switch action.type {
        case .createTask:
            guard let title = action.title else { return false }
            return (try? repository.quickAddTask(title: title, dueDate: action.start, hasTime: action.start != nil,
                                                  minutes: action.durationMinutes ?? 30, priority: action.priority ?? .medium,
                                                  category: category)) != nil
        case .rescheduleTask:
            guard let id = action.taskID, let task = repository.task(id: id), !task.isCompleted, let start = action.start else { return false }
            if let minutes = action.durationMinutes { task.estimatedMinutes = InputValidator.clampDuration(minutes) }
            repository.reschedule(task, to: start, hasTime: true)
            return true
        case .setTaskPriority:
            guard let id = action.taskID, let task = repository.task(id: id), let priority = action.priority else { return false }
            task.priority = priority
            task.updatedAt = repository.now()
            return repository.commit()
        case .createEvent:
            guard let title = action.title, let start = action.start, let end = action.end else { return false }
            var draft = EventDraft(start: start)
            draft.title = title
            draft.start = start
            draft.end = end
            draft.categoryID = category?.id
            return (try? repository.createEvent(from: draft)) != nil
        }
    }
}
