# Contrato do backend da Dayli AI (v1)

O app **nunca** fala diretamente com provedores de IA. Ele chama o backend do Dayli, que guarda as credenciais do provedor, autentica o aparelho, aplica limites e devolve uma proposta tipada.

## Endpoint

`POST {DayliAIBackendURL}/v1/assistant/proposals` — somente HTTPS.

Cabeçalhos enviados pelo app:

| Cabeçalho | Valor |
|---|---|
| `Content-Type` / `Accept` | `application/json` |
| `X-Dayli-Schema-Version` | `1` |
| `Authorization` | `Bearer <token de sessão do aparelho>` (opcional; guardado no Keychain em `ai.session.token`) |

Timeout do cliente: 30 s.

## Requisição

```json
{
  "context": {
    "locale": "pt-BR",
    "timeZone": "America/Sao_Paulo",
    "now": "2026-11-07T08:00:00Z",
    "userMessage": "Organize meu dia de amanhã",
    "tasks": [
      { "id": "UUID", "title": "Tarefa de Trabalho", "priority": 2, "dueDate": "2026-11-07T03:00:00Z",
        "hasTime": false, "durationMinutes": 60, "area": "work" }
    ],
    "busy": [ { "start": "…", "end": "…", "label": "Ocupado" } ],
    "routine": { "wake": {"hour":7,"minute":0}, "sleep": {"hour":23,"minute":0},
                 "workStart": {"hour":9,"minute":0}, "workEnd": {"hour":18,"minute":0},
                 "workdays": [2,3,4,5,6], "bufferMinutes": 10, "maxPersonalFocusMinutes": 180,
                 "studyPreference": "evening", "workoutPreference": "evening" }
  }
}
```

- Títulos só são enviados se a usuária ativar "Enviar títulos das tarefas"; caso contrário vêm como `"Tarefa de Trabalho"`, `"Ocupado"` etc.
- Dados sensíveis (e-mail, CPF, CNPJ, cartão, conta, telefone, sequências longas de dígitos) são removidos no aparelho (`[removido]`).
- `priority`: 0 = baixa, 1 = média, 2 = alta. Datas em ISO 8601.

## Resposta (200)

```json
{
  "version": 1,
  "message": "Preparei uma sugestão para amanhã…",
  "actions": [
    { "type": "rescheduleTask", "taskID": "UUID", "start": "2026-11-08T22:00:00Z", "durationMinutes": 60,
      "title": "Relatório", "rationale": "Prioridade alta." },
    { "type": "createTask", "title": "Estudar", "start": "2026-11-08T22:30:00Z", "durationMinutes": 120,
      "priority": 1, "categoryName": "Estudos" }
  ]
}
```

### Tipos de ação (conjunto fechado)

| `type` | Obrigatórios | Opcionais |
|---|---|---|
| `createTask` | `title` | `start`, `durationMinutes`, `priority`, `categoryName`, `rationale` |
| `createEvent` | `title`, `start`, `durationMinutes` | `categoryName`, `rationale` |
| `rescheduleTask` | `taskID` (de `context.tasks`), `start`, `durationMinutes` | `title`, `rationale` |
| `setTaskPriority` | `taskID`, `priority` | `title`, `rationale` |

Regras aplicadas pelo app (respostas fora delas são descartadas):
- Qualquer `type` desconhecido, tipo de campo errado ou data não ISO 8601 → **toda a resposta é rejeitada**.
- `version` ≠ 1, mais de 20 ações, `message` > 4.000 caracteres ou corpo > 64 KB → rejeitada.
- `start` no passado ou além de 31 dias, `durationMinutes` fora de 5…720, `taskID` desconhecido → ação descartada.
- Conflitos com períodos ocupados geram aviso e a ação começa desmarcada.
- **Nenhuma ação é executada sem confirmação da usuária.** Não há ações de exclusão.

## Erros
Qualquer status fora de 2xx é exibido como indisponibilidade temporária; o restante do app continua funcionando.

## Requisitos recomendados para o backend (não implementado aqui)
- Autenticação de aparelho (ex.: App Attest + token de curta duração).
- Rate limiting por aparelho.
- Retenção zero do conteúdo (ou mínima, documentada), sem uso para treino.
- Logs sem conteúdo das requisições.
- Prompt de sistema que obrigue saída JSON no esquema acima (ex.: *structured outputs* / *tool use* do provedor) e proíba recomendações médicas, financeiras ou jurídicas individualizadas.
