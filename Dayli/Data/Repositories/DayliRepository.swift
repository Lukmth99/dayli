import Foundation
import SwiftData
import DayliCore

/// Ponto único de escrita do app. As telas leem com `@Query` e alteram dados
/// apenas por aqui, para que notificações, widgets e regras de negócio
/// fiquem sempre consistentes.
@MainActor
final class DayliRepository {
    let context: ModelContext
    var calendar: Calendar
    /// Chamado após cada alteração persistida (reprograma notificações e widgets).
    var onChange: (() -> Void)?
    /// Relógio injetável para testes.
    var now: () -> Date = { .now }

    init(context: ModelContext, calendar: Calendar = .dayli) {
        self.context = context
        self.calendar = calendar
    }

    @discardableResult
    func commit() -> Bool {
        let ok = context.saveLogged()
        if ok { onChange?() }
        return ok
    }

    // MARK: Singletons

    func settings() -> AppSettings {
        if let existing = try? context.fetch(FetchDescriptor<AppSettings>()).first { return existing }
        let settings = AppSettings()
        settings.aiBackendURL = AppConfig.defaultAIBackendURL
        context.insert(settings)
        context.saveLogged()
        return settings
    }

    func profile() -> UserProfile {
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first { return existing }
        let profile = UserProfile()
        context.insert(profile)
        context.saveLogged()
        return profile
    }

    func routinePreference() -> RoutinePreference {
        if let existing = try? context.fetch(FetchDescriptor<RoutinePreference>()).first { return existing }
        let pref = RoutinePreference()
        context.insert(pref)
        context.saveLogged()
        return pref
    }

    var routine: RoutineSettings { routinePreference().routine }

    // MARK: Categorias

    func categories() -> [LifeCategory] {
        let descriptor = FetchDescriptor<LifeCategory>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Cria as categorias padrão uma única vez (idempotente).
    func ensureDefaultCategories() {
        let existing = categories()
        let existingAreas = Set(existing.filter(\.isDefault).compactMap(\.area))
        for (index, item) in DefaultCategory.all.enumerated() where !existingAreas.contains(item.area) {
            context.insert(LifeCategory(name: item.name, colorHex: item.colorHex, symbolName: item.symbolName,
                                        area: item.area, isDefault: true, sortOrder: index))
        }
        context.saveLogged()
    }

    func category(for area: LifeArea) -> LifeCategory? {
        categories().first { $0.area == area }
    }

    func category(named name: String) -> LifeCategory? {
        categories().first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    @discardableResult
    func createCategory(name: String, colorHex: String, symbolName: String) -> LifeCategory? {
        guard let clean = InputValidator.sanitizedTitle(name) else { return nil }
        let category = LifeCategory(name: String(clean.prefix(40)), colorHex: colorHex, symbolName: symbolName, area: nil,
                                    isDefault: false, sortOrder: (categories().map(\.sortOrder).max() ?? 0) + 1)
        context.insert(category)
        commit()
        return category
    }

    func deleteCategory(_ category: LifeCategory) {
        // Itens vinculados ficam sem categoria (regra .nullify), nunca são apagados.
        context.delete(category)
        commit()
    }

    // MARK: Onboarding

    func completeOnboarding(name: String, areas: Set<LifeArea>, routine: RoutineSettings) {
        let profile = profile()
        profile.name = InputValidator.sanitizedTitle(name).map { String($0.prefix(60)) } ?? ""
        let settings = settings()
        settings.selectedAreas = areas.isEmpty ? Set(LifeArea.allCases) : areas
        settings.onboardingCompleted = true
        routinePreference().routine = routine
        ensureDefaultCategories()
        commit()
    }

    // MARK: Dados

    /// Exclui todos os dados do Dayli neste aparelho. Eventos do Calendário Apple não são tocados.
    func deleteAllData() throws {
        try context.delete(model: TaskItem.self)
        try context.delete(model: Subtask.self)
        try context.delete(model: CalendarEvent.self)
        try context.delete(model: HabitEntry.self)
        try context.delete(model: Habit.self)
        try context.delete(model: GoalMilestone.self)
        try context.delete(model: Goal.self)
        try context.delete(model: AIMessage.self)
        try context.delete(model: AIProposalRecord.self)
        try context.delete(model: AIConversation.self)
        try context.delete(model: LifeCategory.self)
        try context.delete(model: RoutinePreference.self)
        try context.delete(model: UserProfile.self)
        try context.delete(model: AppSettings.self)
        try context.save()
        KeychainStore().removeAll()
        onChange?()
    }
}
