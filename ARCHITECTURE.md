# Arquitetura do Dayli

## Visão geral

```
┌──────────────── Features (SwiftUI) ────────────────┐
│ Today · Agenda · Tasks · MyLife · Habits · Goals   │   lê com @Query
│ Planner · Assistant · Reviews · Profile · Onboard. │   escreve só via repositório
└───────────────┬────────────────────────────────────┘
                │ AppEnvironment (injeção via .environment)
┌───────────────▼────────────────────────────────────┐
│ DayliRepository (@MainActor)  — único ponto de escrita
│   ├─ Task/Event/Habit/Goal repositories (extensões)
│   └─ onChange → AppEnvironment.didChangeData()
│         ├─ NotificationCoordinator.rebuild() (debounce)
│         └─ WidgetSnapshotWriter.update()
│ Services: CalendarService (EventKit) · AIService · DayContextBuilder
└───────────────┬────────────────────────────────────┘
                │ tipos de valor
┌───────────────▼────────────────────────────────────┐
│ DayliCore (pacote Swift, só Foundation, 100% testável)
│ Recorrência · Planejador · Conflitos · Hábitos · Metas
│ Contrato e validação da IA · Redação de dados sensíveis
│ Planejamento de notificações · Snapshot de widgets
└────────────────────────────────────────────────────┘
```

## Decisões

### MVVM leve + núcleo de domínio puro
- **Regras de negócio** ficam no pacote `DayliCore`, sem dependência de UI/persistência. Isso permite testes rápidos (`swift test`) e reuso pela extensão de widgets.
- **Views** usam `@Query` para leitura reativa e chamam o `DayliRepository` para escrita. Para telas com estado próprio relevante (assistente), há um `@Observable` ViewModel (`AssistantViewModel`). Evitamos criar um ViewModel por tela quando `@Query` + repositório já resolvem — menos camadas, menos código duplicado.
- **Repositório único** (`DayliRepository`) centraliza validação, regras de recorrência e efeitos colaterais (notificações/widgets), garantindo consistência independentemente de quem altera os dados (UI, App Intents, IA).

### Persistência (SwiftData)
- iOS 17+, `VersionedSchema` (`DayliSchemaV1`) + `SchemaMigrationPlan` prontos para evoluir. Procedimento de migração documentado em `Persistence.swift`.
- Todo modelo tem `id: UUID` único e estável. Enums são salvos como `rawValue`; estruturas (recorrência, agenda de hábito, rotina) como `Data` codificada — mudanças futuras não quebram o banco.
- Regras de exclusão: subtarefas, registros de hábito e etapas de meta em **cascata**; categorias com **nullify** (excluir categoria nunca apaga tarefas).
- `#Index` (iOS 18) não foi usado para manter iOS 17; consultas fazem pré-filtro por predicado e o volume esperado é pessoal (testado com 1.000 tarefas).
- **Eventos do Calendário Apple não são persistidos.** São lidos ao vivo via EventKit (`ExternalEvent`) e exibidos como referência. Compromissos criados no Dayli podem ser espelhados no Calendário; guardamos apenas o `eventIdentifier` do espelho para evitar duplicidade na linha do tempo.
- O banco fica no contêiner do app (não no App Group). Widgets recebem apenas um **snapshot JSON mínimo** (`WidgetSnapshot`).

Adaptações de nomes em relação ao escopo:

| Escopo | Implementação | Motivo |
|---|---|---|
| Task | `TaskItem` | Conflito com `Swift.Task` |
| Category | `LifeCategory` | Conflito com o typedef `Category` do runtime Obj‑C |
| ReminderPreference | campos em `AppSettings` | Relação 1:1, evitava modelo redundante |
| RoutinePreference | `RoutinePreference` (com `RoutineSettings` codificado) | — |
| AIProposal | `AIProposalRecord` (persistido) + `AIProposal` (contrato) | Separar auditoria do contrato tipado |
| — | `AIMessage` | Mensagens da `AIConversation` |

### Tarefas recorrentes
Cada ocorrência é um registro. Concluir uma ocorrência gera **somente a próxima** (pendente), com o mesmo `seriesID`. Se a ocorrência estiver muito atrasada, a próxima é a primeira a partir de hoje (sem acúmulo). Reabrir remove a ocorrência gerada se ela ainda não foi tocada. Excluir uma ocorrência não afeta ocorrências já existentes.

### Datas, fusos e horário de verão
Horários de rotina são `TimeOfDay` (hora/minuto) convertidos via `Calendar.date(bySettingHour:…)`; recorrências somam componentes de calendário. Isso mantém o horário local ao atravessar mudanças de DST (há testes com `America/New_York`).

### Planejamento ("Organizar meu dia")
`DayPlanner` (determinístico): janela acordar→dormir, remove períodos ocupados (eventos, eventos externos, tarefas com horário) com respiro configurável, separa horário de trabalho (tarefas de Trabalho vão para dentro do expediente; as demais, para fora), ordena por atrasadas → prazo do dia → prioridade → prazo → duração, aplica limite diário de tarefas pessoais (anti-sobrecarga) e devolve sugestões + itens não encaixados com motivo. Nada é aplicado sem aprovação; compromissos nunca são movidos.

### IA
`AIService` (protocolo) com três implementações: `LocalRulesAIService` (regras locais, offline), `RemoteAIService` (backend HTTPS do Dayli) e `UnavailableAIService`. Todas devolvem `AIProposal` — um conjunto **fechado** de ações tipadas. O fluxo é: contexto mínimo (`AIContextBuilder`, com redação de dados sensíveis) → proposta → decodificação estrita (`AIResponseParser`) → validação (`AIProposalValidator`) → prévia → confirmação → `AIProposalExecutor` (mapeia cada ação para um método conhecido do repositório) → resultado registrado em `AIProposalRecord`.

### Notificações
Reconstrução completa com identificadores determinísticos, disparada (com debounce) após cada alteração e ao voltar ao app. Horizonte de 7 dias, horário de silêncio, categorias silenciadas e limite de 60 pendentes (o iOS permite 64). Regras puras em `NotificationPlanner` (testadas).

### Concorrência
Tudo que toca SwiftData/EventKit/UI é `@MainActor`. Trabalho de IA é `async`. O projeto usa Swift 5 com checagem mínima de concorrência; migração para Swift 6 está no roadmap.

### Design system
Tokens em `Core/DesignSystem/Theme.swift` derivados de `dayli_ios_design_system/DESIGN.md` (Stitch), com variantes de modo escuro e tipografia baseada em estilos de texto do sistema (Dynamic Type). A fonte Inter do protótipo não foi embarcada; usamos SF Pro (nativa, licença e Dynamic Type garantidos).
