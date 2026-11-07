import Foundation

/// Remove padrões de dados sensíveis antes de qualquer envio a serviços externos de IA.
///
/// É uma camada de defesa adicional — não substitui o consentimento nem a minimização
/// de contexto. Pensado para o contexto da usuária (bancária): evita que CPF, CNPJ,
/// números de cartão, conta/agência, e-mails e telefones saiam do aparelho por engano.
public enum SensitiveDataRedactor {
    public static let placeholder = "[removido]"

    private static let patterns: [String] = [
        // E-mail
        #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
        // CNPJ 00.000.000/0000-00
        #"\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b"#,
        // CPF 000.000.000-00
        #"\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b"#,
        // Cartões (13–19 dígitos com espaços ou hífens)
        #"\b(?:\d[ \-]?){13,19}\b"#,
        // Agência / conta com rótulo
        #"(?i)\b(ag[eê]ncia|ag\.?|conta|c/c|cc)\s*:?\s*[\d\-\.]{3,}"#,
        // Telefones BR: (11) 91234-5678, 11912345678, +55...
        #"(?:\+?55\s?)?\(?\d{2}\)?\s?9?\d{4}[\-\s]?\d{4}\b"#,
        // Sequências longas de dígitos (protocolos, contratos, contas)
        #"\b\d{6,}\b"#
    ]

    private static let regexes: [NSRegularExpression] = patterns.compactMap { try? NSRegularExpression(pattern: $0) }

    public static func redact(_ text: String) -> String {
        var result = text
        for regex in regexes {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: placeholder)
        }
        return result
    }

    public static func containsSensitiveData(_ text: String) -> Bool {
        redact(text) != text
    }
}

// MARK: - Contexto mínimo enviado à IA

public struct AIContextPayload: Codable, Sendable, Equatable {
    public struct ContextTask: Codable, Sendable, Equatable {
        public var id: UUID
        public var title: String
        public var priority: Priority
        public var dueDate: Date?
        public var hasTime: Bool
        public var durationMinutes: Int
        public var area: LifeArea?
    }

    public struct ContextBusy: Codable, Sendable, Equatable {
        public var start: Date
        public var end: Date
        public var label: String
    }

    public var locale: String
    public var timeZone: String
    public var now: Date
    public var userMessage: String
    public var tasks: [ContextTask]
    public var busy: [ContextBusy]
    public var routine: RoutineSettings
}

public struct AIContextOptions: Sendable, Equatable {
    /// Se falso, títulos são substituídos por rótulos genéricos ("Tarefa de Trabalho").
    public var shareTitles: Bool
    /// Remove padrões sensíveis de todos os textos (sempre recomendado).
    public var redactSensitive: Bool
    public var maxTasks: Int
    public var maxBusy: Int

    public init(shareTitles: Bool = false, redactSensitive: Bool = true, maxTasks: Int = 40, maxBusy: Int = 60) {
        self.shareTitles = shareTitles
        self.redactSensitive = redactSensitive
        self.maxTasks = maxTasks
        self.maxBusy = maxBusy
    }
}

public enum AIContextBuilder {
    public static func build(message: String, tasks: [PlannableTask], taskHasTime: [UUID: Bool] = [:], busy: [BusyInterval],
                             routine: RoutineSettings, now: Date, timeZone: TimeZone, options: AIContextOptions) -> AIContextPayload {
        func clean(_ s: String) -> String { options.redactSensitive ? SensitiveDataRedactor.redact(s) : s }

        let contextTasks = tasks.prefix(options.maxTasks).map { task -> AIContextPayload.ContextTask in
            let title = options.shareTitles ? clean(task.title) : "Tarefa" + (task.area.map { " de \($0.title)" } ?? "")
            return AIContextPayload.ContextTask(id: task.id, title: title, priority: task.priority, dueDate: task.dueDate,
                                                hasTime: taskHasTime[task.id] ?? false,
                                                durationMinutes: task.estimatedMinutes, area: task.area)
        }
        let contextBusy = busy.sorted { $0.interval.start < $1.interval.start }.prefix(options.maxBusy).map {
            AIContextPayload.ContextBusy(start: $0.interval.start, end: $0.interval.end,
                                         label: options.shareTitles ? clean($0.title) : "Ocupado")
        }
        return AIContextPayload(locale: "pt-BR", timeZone: timeZone.identifier, now: now,
                                userMessage: clean(String(message.prefix(1_000))),
                                tasks: Array(contextTasks), busy: Array(contextBusy), routine: routine)
    }
}
