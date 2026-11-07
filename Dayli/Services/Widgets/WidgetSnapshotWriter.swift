import Foundation
import WidgetKit
import DayliCore

/// Escreve no App Group um resumo mínimo do dia para os widgets.
/// Os widgets nunca acessam o banco completo.
@MainActor
enum WidgetSnapshotWriter {
    static func update(builder: DayContextBuilder, settings: AppSettings, now: Date = .now) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier) else {
            AppLog.widgets.error("App Group indisponível; widgets não serão atualizados")
            return
        }
        let context = builder.context(for: now, now: now)
        let categories = Dictionary(builder.repository.categories().map { ($0.id, $0.colorHex) }, uniquingKeysWith: { a, _ in a })

        let events = context.entries
            .filter { $0.kind != .task && !$0.isAllDay }
            .map { entry in
                WidgetSnapshot.Item(id: entry.id, title: entry.title, start: entry.start, end: entry.end,
                                    colorHex: entry.categoryID.flatMap { categories[$0] }, isTask: false, isCompleted: false, priority: nil)
            }
        let priorityTasks = context.tasks
            .filter { !$0.isCompleted }
            .sorted { ($0.priority, $1.dueDate ?? .distantFuture) > ($1.priority, $0.dueDate ?? .distantFuture) }
            .prefix(5)
            .map { task in
                WidgetSnapshot.Item(id: task.id.uuidString, title: task.title, start: task.hasTime ? task.dueDate : nil, end: task.endDate,
                                    colorHex: task.category?.colorHex, isTask: true, isCompleted: false, priority: task.priority)
            }
        let snapshot = WidgetSnapshot(generatedAt: now, day: context.day, events: events, priorityTasks: Array(priorityTasks),
                                      totalTasks: context.progress.total, completedTasks: context.progress.completed,
                                      hideDetails: settings.widgetHideDetails)
        do {
            try WidgetSnapshotStore.write(snapshot, to: container)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            AppLog.widgets.error("Falha ao gravar snapshot dos widgets")
        }
    }

    static func clear() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier) else { return }
        try? FileManager.default.removeItem(at: WidgetSnapshotStore.url(in: container))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
