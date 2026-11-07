# Progresso — Dayli (continuidade entre sessões)

## Sessão 1 — 2026-11-07 (ambiente: Windows, sem Swift/Xcode)

**Ambiente verificado:** Windows 10, sem `swift`, sem `xcodebuild`, sem distribuição WSL. Nenhuma compilação ou teste pôde ser executado. Todo o código abaixo está **não compilado**.

**Insumos analisados:** 15 exportações do Google Stitch (HTML + PNG) e `dayli_ios_design_system/DESIGN.md` (tokens de cor, tipografia, espaçamentos, raios, componentes). As telas Hoje, Tarefas, Minha Vida e "Nova atividade" foram usadas como referência visual principal.

### Etapas
| Etapa | Estado |
|---|---|
| 1. Fundação (projeto, arquitetura, design system, persistência, navegação) | ✅ escrita |
| 2. Onboarding, Hoje, Agenda, Tarefas, categorias, editores | ✅ escrita |
| 3. Minha Vida, hábitos, metas, rotina, revisões | ✅ escrita (estudos/datas especiais sem modelo dedicado) |
| 4. Calendário Apple, notificações, widgets, App Intents | ✅ escrita |
| 5. Planejador, interface de IA, contrato do backend, confirmação | ✅ escrita (backend fora do repo) |
| 6. Testes, acessibilidade, erros, segurança, documentação | 🟡 testes escritos, **não executados**; documentação ✅ |

### Próxima sessão — fazer primeiro (em um Mac)
1. `cd Packages/DayliCore && swift test` → corrigir falhas.
2. `xcodegen generate` → abrir `Dayli.xcodeproj` → configurar Team/App Group.
3. Compilar e corrigir erros (prováveis pontos de atenção: inferência de isolamento `@MainActor` em closures, APIs SwiftData/EventKit, inits memberwise de views).
4. ⌘U e registrar aqui quantos testes passaram/falharam.
5. Checklist manual em TESTING.md.
6. Adicionar AppIcon e `PrivacyInfo.xcprivacy`.

### Sem Mac disponível
A usuária/dono do projeto não tem Mac. Caminho adotado: compilar e testar via GitHub Actions (`.github/workflows/ios.yml`, runner `macos-15`). Instalação no iPhone exigirá conta Apple Developer + TestFlight (assinatura em nuvem, ex.: Codemagic ou fastlane no Actions).

### Registro de resultados
| Data | Comando | Resultado |
|---|---|---|
| 2026-11-07 | `swift test` (DayliCore, GitHub Actions macos-15) | ✅ 63 testes, 0 falhas |
| 2026-11-07 | `xcodebuild build` | ✅ compilou (1 aviso de concorrência, corrigido) |
| 2026-11-07 (run 1) | `xcodebuild test` | ❌ AIFlowTests travava (ModelContainer local liberado no setUp → corrigido retendo o contêiner); UI tests ✅ 3/3; RepositoryTests não chegaram a rodar |
| 2026-11-07 (run 2) | `xcodebuild test` | ❌ 1 falha real: item de amanhã 00:00 aparecia hoje (`DateInterval.contains` inclui o fim) → corrigido com `includes` semiaberto |
| 2026-11-07 (run 3) | CI completo | ✅ BUILD + TEST SUCCEEDED: 64 testes DayliCore, 22 integração, 3 UI (89, 0 falhas); artefatos simulador (.app zip) e IPA sem assinatura gerados |

### Decisões tomadas nesta sessão
- XcodeGen em vez de `.pbxproj` escrito à mão.
- iOS 17+ (SwiftData, EventKit full access, widgets com `containerBackground`).
- Swift 5 com concorrência mínima (reduz risco de erros sem compilador; migrar para Swift 6 depois).
- Eventos externos nunca persistidos; widgets via snapshot JSON no App Group.
- Assistente local por regras como "modo sem IA", claramente rotulado; IA remota só via backend.
