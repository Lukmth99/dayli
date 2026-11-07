# Dayli — Sua vida, no seu ritmo.

Aplicativo iOS nativo (Swift, SwiftUI, SwiftData) de organização pessoal: rotina, agenda, tarefas, hábitos, metas e um assistente que **propõe** mudanças, mas nunca as aplica sem confirmação.

> ⚠️ **Estado da validação:** o código foi escrito em um ambiente Windows **sem Xcode nem toolchain Swift**. Nada foi compilado nem executado ainda. Antes de qualquer outra coisa, siga "Primeira compilação" abaixo em um Mac e registre os resultados em [PROGRESS.md](PROGRESS.md).

## Requisitos

- macOS 14+ com **Xcode 16** ou mais recente (SDK iOS 17+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iPhone ou simulador com **iOS 17.0+**

## Primeira compilação

```bash
# 1. Testes do núcleo de regras (rápido, não precisa de simulador)
cd Packages/DayliCore
swift test

# 2. Gerar o projeto Xcode
cd ../..
xcodegen generate

# 3. Abrir no Xcode
open Dayli.xcodeproj
```

No Xcode:

1. Em *Signing & Capabilities* de **Dayli** e **DayliWidgets**, escolha seu *Team* (ou preencha `DEVELOPMENT_TEAM` no `project.yml`).
2. Se os identificadores `app.dayli.ios` / `group.app.dayli.shared` estiverem indisponíveis na sua conta, troque-os no `project.yml` (procure também por `DayliAppGroupIdentifier`).
3. Rode o esquema **Dayli** (⌘R). Testes: ⌘U.

Via linha de comando:

```bash
xcodebuild test -project Dayli.xcodeproj -scheme Dayli \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Estrutura

```
Packages/DayliCore/      Regras de negócio puras (Foundation) + testes
Dayli/
  App/                   Ponto de entrada, navegação, injeção de dependências
  Core/                  Design system, utilitários, Keychain
  Data/                  Modelos SwiftData, esquema versionado, repositórios
  Services/              Notificações, EventKit, IA, planejamento, widgets
  Features/              Telas (Hoje, Agenda, Tarefas, Minha Vida, Perfil…)
  AppIntents/            Siri e Atalhos
  Resources/             Assets, Info.plist/entitlements (gerados pelo XcodeGen)
DayliWidgets/            Extensão WidgetKit
DayliTests/              Testes de integração (SwiftData em memória)
DayliUITests/            Testes de interface (fluxos críticos)
docs/                    Contrato do backend de IA e rascunho de privacidade
*/code.html, screen.png  Exportações do Google Stitch (referência visual)
```

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Arquitetura e decisões |
| [FEATURES.md](FEATURES.md) | Funcionalidades e estado de cada uma |
| [SECURITY.md](SECURITY.md) | Controles de segurança e limitações |
| [TESTING.md](TESTING.md) | Estratégia e execução de testes |
| [ROADMAP.md](ROADMAP.md) | Próximos passos |
| [PROGRESS.md](PROGRESS.md) | Acompanhamento entre sessões |
| [docs/AI_BACKEND_CONTRACT.md](docs/AI_BACKEND_CONTRACT.md) | Contrato da API de IA |
| [docs/PRIVACY.md](docs/PRIVACY.md) | Rascunho de política de privacidade (LGPD / App Store) |

## IA

Sem configuração extra, o app usa o **assistente local** (regras determinísticas, offline, sem IA generativa — identificado assim na interface). A IA remota exige um backend próprio que siga [docs/AI_BACKEND_CONTRACT.md](docs/AI_BACKEND_CONTRACT.md); a URL é configurada em *Perfil › Inteligência artificial* (ou `DayliAIBackendURL` no `project.yml`). **Nunca** coloque chaves de provedores de IA no app.
