import Foundation
import SwiftData
import DayliCore

/// Exportação dos dados do Dayli em JSON legível (portabilidade — LGPD art. 18, V).
/// Não inclui eventos do Calendário Apple (não pertencem ao Dayli) nem segredos do Keychain.
@MainActor
enum DataExporter {
    struct Export: Encodable {
        let exportedAt: Date
        let appVersion: String
        let schemaVersion: String
        let profile: Profile?
        let routine: RoutineSettings
        let categories: [CategoryOut]
        let tasks: [TaskOut]
        let events: [EventOut]
        let habits: [HabitOut]
        let goals: [GoalOut]

        struct Profile: Encodable { let name: String }
        struct CategoryOut: Encodable { let id: UUID; let name: String; let colorHex: String; let area: String? }
        struct TaskOut: Encodable {
            let id: UUID; let title: String; let notes: String; let priority: String; let dueDate: Date?; let hasTime: Bool
            let estimatedMinutes: Int; let completedAt: Date?; let category: String?; let recurrence: RecurrenceRule?; let subtasks: [String]
        }
        struct EventOut: Encodable {
            let id: UUID; let title: String; let start: Date; let end: Date; let isAllDay: Bool; let location: String; let notes: String
            let category: String?; let recurrence: RecurrenceRule?
        }
        struct HabitOut: Encodable {
            let id: UUID; let title: String; let schedule: HabitSchedule; let targetCount: Int; let unit: String; let archived: Bool
            let entries: [Entry]
            struct Entry: Encodable { let day: Date; let count: Int }
        }
        struct GoalOut: Encodable {
            let id: UUID; let title: String; let details: String; let startDate: Date; let endDate: Date; let progressKind: String
            let targetValue: Double?; let currentValue: Double; let unit: String; let status: String; let milestones: [String]
        }
    }

    static func makeFile(repository: DayliRepository) throws -> URL {
        let context = repository.context
        let export = Export(
            exportedAt: .now,
            appVersion: AppConfig.appVersion,
            schemaVersion: { let v = DayliSchemaV1.versionIdentifier; return "\(v.major).\(v.minor).\(v.patch)" }(),
            profile: (try? context.fetch(FetchDescriptor<UserProfile>()).first).map { Export.Profile(name: $0.name) },
            routine: repository.routine,
            categories: repository.categories().map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, area: $0.areaRaw) },
            tasks: repository.allTasks().map {
                .init(id: $0.id, title: $0.title, notes: $0.notes, priority: $0.priority.title, dueDate: $0.dueDate, hasTime: $0.hasTime,
                      estimatedMinutes: $0.estimatedMinutes, completedAt: $0.completedAt, category: $0.category?.name,
                      recurrence: $0.recurrence, subtasks: $0.sortedSubtasks.map(\.title))
            },
            events: repository.allEvents().map {
                .init(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay, location: $0.location,
                      notes: $0.notes, category: $0.category?.name, recurrence: $0.recurrence)
            },
            habits: ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).map { habit in
                .init(id: habit.id, title: habit.title, schedule: habit.schedule, targetCount: habit.targetCount, unit: habit.unit,
                      archived: habit.isArchived, entries: habit.entries.sorted { $0.day < $1.day }.map { .init(day: $0.day, count: $0.count) })
            },
            goals: repository.goals().map {
                .init(id: $0.id, title: $0.title, details: $0.details, startDate: $0.startDate, endDate: $0.endDate,
                      progressKind: $0.progressKindRaw, targetValue: $0.targetValue, currentValue: $0.currentValue, unit: $0.unit,
                      status: $0.statusRaw, milestones: $0.sortedMilestones.map(\.title))
            })

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dayli-export-\(stamp).json")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

/// Dados de demonstração — **explicitamente identificados** (`isDemo = true`) e removíveis.
/// Nunca são carregados automaticamente.
@MainActor
enum DemoDataSeeder {
    static func load(into repository: DayliRepository) {
        let calendar = repository.calendar
        let today = calendar.startOfDay(for: .now)
        repository.ensureDefaultCategories()
        func cat(_ area: LifeArea) -> LifeCategory? { repository.category(for: area) }
        func at(_ h: Int, _ m: Int = 0, dayOffset: Int = 0) -> Date {
            TimeOfDay(hour: h, minute: m).date(on: calendar.addingDays(dayOffset, to: today), calendar: calendar)
        }
        let context = repository.context

        let events: [(String, Date, Date, LifeArea)] = [
            ("[Demo] Reunião de fechamento", at(10, 30), at(11, 15), .work),
            ("[Demo] Almoço", at(12), at(13), .personal),
            ("[Demo] Treino de pernas", at(18, 30), at(19, 20), .fitness),
            ("[Demo] Aula de Auditoria", at(20), at(21, 15), .studies)
        ]
        for (title, start, end, area) in events {
            context.insert(CalendarEvent(title: title, start: start, end: end, category: cat(area), alertOffsetMinutes: nil, isDemo: true))
        }
        let tasks: [(String, Priority, Date?, Bool, LifeArea)] = [
            ("[Demo] Finalizar relatório trimestral", .high, at(14), true, .work),
            ("[Demo] Revisar artigos para a prova", .medium, today, false, .studies),
            ("[Demo] Agendar manutenção do carro", .low, calendar.addingDays(2, to: today), false, .personal),
            ("[Demo] Comprar vitaminas", .low, nil, false, .health)
        ]
        for (title, priority, due, hasTime, area) in tasks {
            context.insert(TaskItem(title: title, priority: priority, dueDate: due, hasTime: hasTime, estimatedMinutes: 45, category: cat(area), isDemo: true))
        }
        context.insert(Habit(title: "[Demo] Beber água", symbolName: "drop", colorHex: "#9BB8CD", targetCount: 8, unit: "copos", category: cat(.health), isDemo: true))
        context.insert(Habit(title: "[Demo] Ler", symbolName: "book", colorHex: "#B8A3CE", schedule: .weekdays([2, 4, 6]), category: cat(.studies), isDemo: true))
        context.insert(Goal(title: "[Demo] Estudar 20 horas no mês", startDate: today, endDate: calendar.addingDays(30, to: today),
                            progressKind: .manual, targetValue: 20, currentValue: 6, unit: "horas", category: cat(.studies), isDemo: true))
        repository.commit()
    }

    static func remove(from repository: DayliRepository) {
        let context = repository.context
        // Exclusão item a item para respeitar as regras de cascata dos relacionamentos.
        (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDemo })))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.isDemo })))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.isDemo })))?.forEach { context.delete($0) }
        (try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.isDemo })))?.forEach { context.delete($0) }
        repository.commit()
    }

    static func hasDemoData(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isDemo })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
