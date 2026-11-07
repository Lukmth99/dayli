import Foundation
import SwiftData
import DayliCore

/// Rascunho editável de uma tarefa (usado pelo formulário e por App Intents/IA).
struct TaskDraft: Equatable {
    var title = ""
    var notes = ""
    var priority: Priority = .medium
    var hasDate = false
    var dueDate = Date.now
    var hasTime = false
    var estimatedMinutes = 30
    var categoryID: UUID?
    var reminderOffsetMinutes: Int?
    var recurrence: RecurrenceRule?
    var subtasks: [SubtaskDraft] = []

    struct SubtaskDraft: Equatable, Identifiable {
        var id = UUID()
        var title: String
        var isDone = false
    }

    init() {}

    init(task: TaskItem) {
        title = task.title
        notes = task.notes
        priority = task.priority
        hasDate = task.dueDate != nil
        dueDate = task.dueDate ?? .now
        hasTime = task.hasTime
        estimatedMinutes = task.estimatedMinutes
        categoryID = task.category?.id
        reminderOffsetMinutes = task.reminderOffsetMinutes
        recurrence = task.recurrence
        subtasks = task.sortedSubtasks.map { SubtaskDraft(id: $0.id, title: $0.title, isDone: $0.isDone) }
    }
}

enum RepositoryError: LocalizedError, Equatable {
    case invalidTitle
    case invalidDateRange
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidTitle: return "Dê um nome para continuar."
        case .invalidDateRange: return "O término precisa ser depois do início."
        case .saveFailed: return "Não foi possível salvar agora. Tente novamente."
        }
    }
}

extension DayliRepository {
    // MARK: Consultas

    func allTasks() -> [TaskItem] {
        (try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    func pendingTasks() -> [TaskItem] {
        let pending = TaskStatus.pending.rawValue
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.statusRaw == pending })
        return (try? context.fetch(descriptor)) ?? []
    }

    func task(id: UUID) -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Tarefas do dia: com vencimento no dia + pendentes de dias anteriores (se o dia for hoje)
    /// + concluídas no dia.
    func tasks(for day: Date) -> [TaskItem] {
        let interval = calendar.dayInterval(for: day)
        let isToday = calendar.isDate(day, inSameDayAs: now())
        return allTasks().filter { task in
            if let completedAt = task.completedAt, task.isCompleted {
                if interval.contains(completedAt) { return true }
                if let due = task.dueDate, interval.contains(due) { return true }
                return false
            }
            guard let due = task.dueDate else { return false }
            if interval.contains(due) { return true }
            return isToday && due < interval.start
        }
    }

    // MARK: Escrita

    @discardableResult
    func createTask(from draft: TaskDraft) throws -> TaskItem {
        guard let title = InputValidator.sanitizedTitle(draft.title) else { throw RepositoryError.invalidTitle }
        let task = TaskItem(title: title)
        context.insert(task)
        apply(draft, to: task, title: title)
        guard commit() else { throw RepositoryError.saveFailed }
        return task
    }

    func updateTask(_ task: TaskItem, from draft: TaskDraft) throws {
        guard let title = InputValidator.sanitizedTitle(draft.title) else { throw RepositoryError.invalidTitle }
        apply(draft, to: task, title: title)
        guard commit() else { throw RepositoryError.saveFailed }
    }

    private func apply(_ draft: TaskDraft, to task: TaskItem, title: String) {
        task.title = title
        task.notes = InputValidator.sanitizedNotes(draft.notes)
        task.priority = draft.priority
        if draft.hasDate {
            task.dueDate = draft.hasTime ? draft.dueDate : calendar.startOfDay(for: draft.dueDate)
            task.hasTime = draft.hasTime
        } else {
            task.dueDate = nil
            task.hasTime = false
        }
        task.estimatedMinutes = InputValidator.clampDuration(draft.estimatedMinutes)
        task.category = draft.categoryID.flatMap { id in categories().first { $0.id == id } }
        task.reminderOffsetMinutes = draft.hasDate ? draft.reminderOffsetMinutes : nil
        // Recorrência exige data.
        let rule = draft.hasDate ? draft.recurrence : nil
        if rule != task.recurrence {
            task.recurrenceAnchor = nil
            task.recurrence = rule
        }
        syncSubtasks(draft.subtasks, into: task)
        task.updatedAt = now()
    }

    private func syncSubtasks(_ drafts: [TaskDraft.SubtaskDraft], into task: TaskItem) {
        let valid = drafts.compactMap { d -> TaskDraft.SubtaskDraft? in
            guard let t = InputValidator.sanitizedTitle(d.title) else { return nil }
            return TaskDraft.SubtaskDraft(id: d.id, title: t, isDone: d.isDone)
        }
        let keep = Set(valid.map(\.id))
        for sub in task.subtasks where !keep.contains(sub.id) {
            context.delete(sub)
        }
        for (index, d) in valid.enumerated() {
            if let existing = task.subtasks.first(where: { $0.id == d.id }) {
                existing.title = d.title
                existing.isDone = d.isDone
                existing.order = index
            } else {
                let sub = Subtask(id: d.id, title: d.title, isDone: d.isDone, order: index)
                context.insert(sub)
                sub.task = task
            }
        }
    }

    /// Conclui a tarefa. Em tarefas recorrentes, conclui **somente esta ocorrência**
    /// e cria a próxima ocorrência pendente.
    @discardableResult
    func complete(_ task: TaskItem) -> TaskItem? {
        guard !task.isCompleted else { return nil }
        task.status = .completed
        task.completedAt = now()
        task.updatedAt = now()

        var nextTask: TaskItem?
        if let rule = task.recurrence, let due = task.dueDate {
            let anchor = task.recurrenceAnchor ?? due
            if let nextDue = TaskRecurrenceEngine.nextDueDate(rule: rule, anchor: anchor, currentDue: due, now: now(), calendar: calendar) {
                let next = TaskItem(title: task.title, notes: task.notes, priority: task.priority, dueDate: nextDue, hasTime: task.hasTime,
                                    estimatedMinutes: task.estimatedMinutes, category: task.category,
                                    reminderOffsetMinutes: task.reminderOffsetMinutes, recurrence: nil, isDemo: task.isDemo)
                next.recurrenceData = task.recurrenceData
                next.recurrenceAnchor = anchor
                next.seriesID = task.seriesID
                next.generatedFromTaskID = task.id
                context.insert(next)
                for sub in task.sortedSubtasks {
                    let copy = Subtask(title: sub.title, isDone: false, order: sub.order)
                    context.insert(copy)
                    copy.task = next
                }
                nextTask = next
            }
            // A ocorrência concluída deixa de gerar novas ocorrências.
            task.recurrenceData = nil
        }
        commit()
        return nextTask
    }

    /// Reabre uma tarefa concluída. Se a conclusão havia gerado a próxima ocorrência
    /// e ela ainda está intacta (pendente e sem alterações), ela é removida para evitar duplicidade.
    func reopen(_ task: TaskItem) {
        guard task.isCompleted else { return }
        let taskID = task.id
        if let generated = allTasks().first(where: { $0.generatedFromTaskID == taskID && !$0.isCompleted }) {
            // Devolve a recorrência para esta ocorrência; remove a próxima só se ela não foi editada.
            task.recurrenceData = generated.recurrenceData
            if generated.updatedAt == generated.createdAt && generated.subtasks.allSatisfy({ !$0.isDone }) {
                context.delete(generated)
            } else {
                generated.recurrenceData = nil
            }
        }
        task.status = .pending
        task.completedAt = nil
        task.updatedAt = now()
        commit()
    }

    func toggleCompletion(_ task: TaskItem) {
        if task.isCompleted { reopen(task) } else { complete(task) }
    }

    @discardableResult
    func duplicate(_ task: TaskItem) -> TaskItem {
        let copy = TaskItem(title: task.title, notes: task.notes, priority: task.priority, dueDate: task.dueDate, hasTime: task.hasTime,
                            estimatedMinutes: task.estimatedMinutes, category: task.category,
                            reminderOffsetMinutes: task.reminderOffsetMinutes, recurrence: task.recurrence, isDemo: task.isDemo)
        context.insert(copy)
        for sub in task.sortedSubtasks {
            let s = Subtask(title: sub.title, isDone: false, order: sub.order)
            context.insert(s)
            s.task = copy
        }
        commit()
        return copy
    }

    /// - Parameter countsAsReschedule: falso quando a tarefa apenas recebe um horário pela
    ///   primeira vez (ex.: "Organizar meu dia"), para não inflar o indicador de reagendamentos.
    func reschedule(_ task: TaskItem, to date: Date, hasTime: Bool, countsAsReschedule: Bool = true) {
        task.dueDate = hasTime ? date : calendar.startOfDay(for: date)
        task.hasTime = hasTime
        if countsAsReschedule { task.rescheduleCount += 1 }
        task.updatedAt = now()
        commit()
    }

    func rescheduleToTomorrow(_ task: TaskItem) {
        let date = TaskTiming.rescheduledToTomorrow(dueDate: task.dueDate, hasTime: task.hasTime, now: now(), calendar: calendar)
        reschedule(task, to: date, hasTime: task.hasTime)
    }

    func move(_ task: TaskItem, to category: LifeCategory?) {
        task.category = category
        task.updatedAt = now()
        commit()
    }

    func toggleSubtask(_ subtask: Subtask) {
        subtask.isDone.toggle()
        subtask.task?.updatedAt = now()
        commit()
    }

    func delete(_ task: TaskItem) {
        context.delete(task)
        commit()
    }

    /// Criação rápida (barra de adição, Siri, IA). Sem data → "Sem data".
    @discardableResult
    func quickAddTask(title: String, dueDate: Date?, hasTime: Bool = false, minutes: Int = 30, priority: Priority = .medium, category: LifeCategory? = nil) throws -> TaskItem {
        var draft = TaskDraft()
        draft.title = title
        draft.hasDate = dueDate != nil
        draft.dueDate = dueDate ?? now()
        draft.hasTime = hasTime && dueDate != nil
        draft.estimatedMinutes = minutes
        draft.priority = priority
        draft.categoryID = category?.id
        return try createTask(from: draft)
    }
}
