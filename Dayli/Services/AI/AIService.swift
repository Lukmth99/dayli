import Foundation
import DayliCore

/// Contrato de qualquer provedor do assistente. Recebe apenas o contexto mínimo
/// autorizado e devolve uma proposta tipada — nunca executa alterações.
protocol AIService: Sendable {
    var kind: AIServiceKind { get }
    func propose(for payload: AIContextPayload) async throws -> AIProposal
}

enum AIServiceKind: Equatable {
    /// Assistente local baseado em regras (sem IA generativa). Roda no aparelho.
    case localRules
    /// Backend do Dayli (que guarda as credenciais do provedor de IA).
    case remote
    case unavailable

    var title: String {
        switch self {
        case .localRules: return "Assistente local (regras, sem IA generativa)"
        case .remote: return "Dayli AI (servidor)"
        case .unavailable: return "Indisponível"
        }
    }

    /// O contexto sai do aparelho?
    var sendsDataOffDevice: Bool { self == .remote }
}

enum AIServiceError: LocalizedError, Equatable {
    case notConfigured
    case consentRequired
    case insecureURL
    case offline
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "A IA remota não está configurada. O assistente local e o restante do app continuam funcionando."
        case .consentRequired: return "Para usar a IA remota, é preciso autorizar o envio do contexto em Perfil › Inteligência artificial."
        case .insecureURL: return "O endereço do servidor de IA precisa usar HTTPS."
        case .offline: return "Sem conexão com a internet. O assistente local continua disponível."
        case .server(let code): return "O servidor de IA não respondeu como esperado (código \(code))."
        case .invalidResponse: return "A resposta do assistente não pôde ser validada e foi descartada com segurança."
        }
    }
}

struct UnavailableAIService: AIService {
    var kind: AIServiceKind { .unavailable }
    func propose(for payload: AIContextPayload) async throws -> AIProposal { throw AIServiceError.notConfigured }
}

/// Cliente do backend do Dayli. O backend autentica o aparelho, aplica limites
/// e chama o provedor de IA com as próprias credenciais (nunca embarcadas no app).
/// Contrato documentado em docs/AI_BACKEND_CONTRACT.md.
struct RemoteAIService: AIService {
    let baseURL: URL
    let sessionToken: String?
    var session: URLSession = .shared

    var kind: AIServiceKind { .remote }

    init(baseURL: URL, sessionToken: String?, session: URLSession = .shared) throws {
        guard baseURL.scheme?.lowercased() == "https" else { throw AIServiceError.insecureURL }
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.session = session
    }

    func propose(for payload: AIContextPayload) async throws -> AIProposal {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/assistant/proposals"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "X-Dayli-Schema-Version")
        if let sessionToken, !sessionToken.isEmpty {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try AIResponseParser.makeEncoder().encode(["context": payload])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            let offlineCodes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed]
            if offlineCodes.contains(error.code) { throw AIServiceError.offline }
            throw AIServiceError.server(error.errorCode)
        }
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AIServiceError.server(http.statusCode) }
        do {
            return try AIResponseParser.parse(data)
        } catch {
            AppLog.ai.error("Resposta da IA rejeitada na validação")
            throw AIServiceError.invalidResponse
        }
    }
}
