import Foundation

// MARK: - Contrato tipado das propostas da IA
//
// A IA nunca altera dados diretamente. Ela devolve uma `AIProposal` (JSON tipado),
// que é decodificada de forma estrita, validada contra as regras do app e exibida
// como prévia. Só ações aprovadas pela usuária são executadas pelo app.

public struct AIProposal: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public static let maxActions = 20

    public var version: Int
    /// Texto para a usuária (resposta, resumo da proposta).
    public var message: String
    public var actions: [AIAction]

    public init(version: Int = AIProposal.currentVersion, message: String, actions: [AIAction]) {
        self.version = version
        self.message = message
        self.actions = actions
    }
}

public struct AIAction: Codable, Hashable, Sendable, Identifiable {
    /// Conjunto fechado de ações. Qualquer outro valor invalida a resposta inteira.
    public enum ActionType: String, Codable, CaseIterable, Sendable {
        case createTask
        case rescheduleTask
        case setTaskPriority
        case createEvent
    }

    public var id: UUID
    public var type: ActionType
    public var taskID: UUID?
    public var title: String?
    public var start: Date?
    public var durationMinutes: Int?
    public var priority: Priority?
    public var categoryName: String?
    public var rationale: String?

    public init(id: UUID = UUID(), type: ActionType, taskID: UUID? = nil, title: String? = nil, start: Date? = nil,
                durationMinutes: Int? = nil, priority: Priority? = nil, categoryName: String? = nil, rationale: String? = nil) {
        self.id = id
        self.type = type
        self.taskID = taskID
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.priority = priority
        self.categoryName = categoryName
        self.rationale = rationale
    }

    enum CodingKeys: String, CodingKey {
        case id, type, taskID, title, start, durationMinutes, priority, categoryName, rationale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // O id é atribuído pelo app quando o modelo não envia um.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decode(ActionType.self, forKey: .type)
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        start = try c.decodeIfPresent(Date.self, forKey: .start)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority)
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        rationale = try c.decodeIfPresent(String.self, forKey: .rationale)
    }

    public var end: Date? {
        guard let start, let durationMinutes else { return nil }
        return start.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

public enum AIResponseError: Error, Equatable, LocalizedError {
    case malformed
    case unsupportedVersion(Int)
    case tooManyActions(Int)
    case messageTooLong

    public var errorDescription: String? {
        switch self {
        case .malformed: return "A resposta do assistente não pôde ser interpretada com segurança."
        case .unsupportedVersion(let v): return "Versão de resposta não suportada (\(v))."
        case .tooManyActions(let n): return "A proposta tinha ações demais (\(n)). Tente um pedido mais específico."
        case .messageTooLong: return "A resposta do assistente excedeu o tamanho permitido."
        }
    }
}

public enum AIResponseParser {
    public static let maxPayloadBytes = 64 * 1024
    public static let maxMessageLength = 4_000

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Decodificação estrita: tipo de ação desconhecido, datas inválidas ou campos
    /// com tipos errados invalidam toda a resposta.
    public static func parse(_ data: Data) throws -> AIProposal {
        guard data.count <= maxPayloadBytes else { throw AIResponseError.malformed }
        let proposal: AIProposal
        do {
            proposal = try makeDecoder().decode(AIProposal.self, from: data)
        } catch {
            throw AIResponseError.malformed
        }
        guard proposal.version == AIProposal.currentVersion else { throw AIResponseError.unsupportedVersion(proposal.version) }
        guard proposal.actions.count <= AIProposal.maxActions else { throw AIResponseError.tooManyActions(proposal.actions.count) }
        guard proposal.message.count <= maxMessageLength else { throw AIResponseError.messageTooLong }
        return proposal
    }
}

// MARK: - Validação de regras

public struct AIValidationContext: Sendable {
    public var knownTaskIDs: Set<UUID>
    public var busy: [BusyInterval]
    public var now: Date
    public var horizonDays: Int
    public var calendar: Calendar

    public init(knownTaskIDs: Set<UUID>, busy: [BusyInterval], now: Date, horizonDays: Int = 31, calendar: Calendar) {
        self.knownTaskIDs = knownTaskIDs
        self.busy = busy
        self.now = now
        self.horizonDays = horizonDays
        self.calendar = calendar
    }
}

public enum AIActionRejection: String, Error, Equatable, Sendable {
    case missingTitle
    case unknownTask
    case missingTaskID
    case missingStart
    case startInPast
    case beyondHorizon
    case invalidDuration
    case missingPriority

    public var message: String {
        switch self {
        case .missingTitle: return "Sem título válido."
        case .unknownTask: return "Tarefa não encontrada ou não autorizada."
        case .missingTaskID: return "Tarefa não informada."
        case .missingStart: return "Horário não informado."
        case .startInPast: return "Horário no passado."
        case .beyondHorizon: return "Data muito distante."
        case .invalidDuration: return "Duração inválida."
        case .missingPriority: return "Prioridade não informada."
        }
    }
}

public struct ValidatedAIAction: Identifiable, Hashable, Sendable {
    public var id: UUID { action.id }
    public var action: AIAction
    /// Avisos não bloqueantes (ex.: conflito de horário). Ações com aviso começam desmarcadas.
    public var warnings: [String]

    public init(action: AIAction, warnings: [String]) {
        self.action = action
        self.warnings = warnings
    }
}

public struct RejectedAIAction: Identifiable, Hashable, Sendable {
    public var id: UUID { action.id }
    public var action: AIAction
    public var reason: AIActionRejection
}

public struct AIValidationResult: Sendable {
    public var message: String
    public var valid: [ValidatedAIAction]
    public var rejected: [RejectedAIAction]
}

public enum AIProposalValidator {
    public static func validate(_ proposal: AIProposal, context: AIValidationContext) -> AIValidationResult {
        var valid: [ValidatedAIAction] = []
        var rejected: [RejectedAIAction] = []
        var plannedIntervals: [BusyInterval] = []
        let horizon = context.calendar.addingDays(context.horizonDays, to: context.now)

        for var action in proposal.actions {
            // Sanitiza textos vindos do modelo.
            if let title = action.title { action.title = InputValidator.sanitizedTitle(title) }
            if let rationale = action.rationale { action.rationale = String(InputValidator.sanitizedNotes(rationale).prefix(300)) }
            if let category = action.categoryName { action.categoryName = InputValidator.sanitizedTitle(category) }

            if let problem = check(action, context: context, horizon: horizon) {
                rejected.append(RejectedAIAction(action: action, reason: problem))
                continue
            }

            var warnings: [String] = []
            if let start = action.start, let end = action.end {
                let candidate = DateInterval(start: start, end: end)
                let excluded = action.taskID.map { "task:\($0.uuidString)" }
                let clashes = ConflictDetector.conflicts(for: candidate, excludingID: excluded, in: context.busy + plannedIntervals)
                if !clashes.isEmpty {
                    warnings.append("Conflita com: " + clashes.map(\.title).prefix(3).joined(separator: ", "))
                }
                plannedIntervals.append(BusyInterval(id: "proposal:\(action.id)", title: action.title ?? "Sugestão", interval: candidate))
            }
            valid.append(ValidatedAIAction(action: action, warnings: warnings))
        }
        let message = String(InputValidator.sanitizedNotes(proposal.message).prefix(AIResponseParser.maxMessageLength))
        return AIValidationResult(message: message, valid: valid, rejected: rejected)
    }

    private static func check(_ action: AIAction, context: AIValidationContext, horizon: Date) -> AIActionRejection? {
        func checkTime(required: Bool) -> AIActionRejection? {
            guard let start = action.start else { return required ? .missingStart : nil }
            if start < context.now.addingTimeInterval(-60) { return .startInPast }
            if start > horizon { return .beyondHorizon }
            if let minutes = action.durationMinutes, !(5...(12 * 60)).contains(minutes) { return .invalidDuration }
            if required && action.durationMinutes == nil { return .invalidDuration }
            return nil
        }

        switch action.type {
        case .createTask:
            guard action.title != nil else { return .missingTitle }
            if let minutes = action.durationMinutes, !(5...(12 * 60)).contains(minutes) { return .invalidDuration }
            return checkTime(required: false)
        case .createEvent:
            guard action.title != nil else { return .missingTitle }
            return checkTime(required: true)
        case .rescheduleTask:
            guard let id = action.taskID else { return .missingTaskID }
            guard context.knownTaskIDs.contains(id) else { return .unknownTask }
            return checkTime(required: true)
        case .setTaskPriority:
            guard let id = action.taskID else { return .missingTaskID }
            guard context.knownTaskIDs.contains(id) else { return .unknownTask }
            guard action.priority != nil else { return .missingPriority }
            return nil
        }
    }
}
