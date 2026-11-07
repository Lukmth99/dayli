import Foundation
import SwiftData
import DayliCore

/// Versão 1 do esquema. Ao alterar modelos de forma incompatível:
/// 1. Copie os modelos atuais para `DayliSchemaV1` (como tipos aninhados) congelando-os.
/// 2. Crie `DayliSchemaV2` com os modelos novos.
/// 3. Adicione um `MigrationStage` (lightweight ou custom) em `DayliMigrationPlan.stages`.
/// Mudanças aditivas com valor padrão são migradas automaticamente (lightweight).
enum DayliSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [UserProfile.self, AppSettings.self, RoutinePreference.self, LifeCategory.self,
         TaskItem.self, Subtask.self, CalendarEvent.self, Habit.self, HabitEntry.self,
         Goal.self, GoalMilestone.self, AIConversation.self, AIMessage.self, AIProposalRecord.self]
    }
}

enum DayliMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [DayliSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum PersistenceError: LocalizedError {
    case containerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "Não foi possível abrir seus dados neste momento."
        }
    }
}

@MainActor
enum PersistenceController {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uitesting") }

    private static var cached: Result<ModelContainer, Error>?

    /// Contêiner compartilhado pelo app e pelos App Intents (mesmo processo).
    static func sharedContainer() throws -> ModelContainer {
        if let cached { return try cached.get() }
        let result = Result { try makeContainer(inMemory: isUITesting) }
        cached = result
        return try result.get()
    }

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema(versionedSchema: DayliSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration("Dayli", schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration("Dayli", schema: schema, isStoredInMemoryOnly: false, allowsSave: true,
                                               groupContainer: .none, cloudKitDatabase: .none)
        }
        do {
            return try ModelContainer(for: schema, migrationPlan: DayliMigrationPlan.self, configurations: [configuration])
        } catch {
            AppLog.persistence.error("Falha ao abrir o banco: \(String(describing: type(of: error)), privacy: .public)")
            throw PersistenceError.containerUnavailable(String(describing: error))
        }
    }
}

extension ModelContext {
    /// Salva e registra falhas sem expor dados pessoais nos logs.
    @discardableResult
    func saveLogged() -> Bool {
        do {
            if hasChanges { try save() }
            return true
        } catch {
            AppLog.persistence.error("Falha ao salvar: \(String(describing: type(of: error)), privacy: .public)")
            rollback()
            return false
        }
    }
}
