# Segurança e privacidade — controles e limitações

Este documento descreve controles **implementados no código**. Ele não constitui certificação nem garantia de conformidade legal; uma revisão de segurança e jurídica independente é necessária antes da publicação.

## Controles implementados

| Área | Controle | Onde |
|---|---|---|
| Armazenamento local | SwiftData no contêiner do app; entitlement de proteção de dados `NSFileProtectionCompleteUntilFirstUserAuthentication`; sem CloudKit | `Persistence.swift`, `project.yml` |
| Widgets | Recebem só um snapshot mínimo (títulos, horários, contagens); opção de ocultar títulos na tela bloqueada | `WidgetSnapshotWriter.swift`, `WidgetSnapshot` |
| Segredos | Nenhuma chave no código. Token de sessão do backend (se houver) no Keychain com `AfterFirstUnlockThisDeviceOnly` | `KeychainStore.swift` |
| Rede | Somente HTTPS (validação de esquema na configuração e no cliente); ATS padrão (sem exceções) | `AIService.swift` |
| IA — consentimento | Desligada por padrão; consentimento explícito com data registrada; revogável | `AISettingsView` |
| IA — minimização | Títulos não são enviados por padrão (rótulos genéricos); limite de itens; horizonte de 8 dias | `AIContextBuilder` |
| IA — redação | Remoção de e-mail, CPF, CNPJ, cartões, agência/conta, telefones e sequências longas de dígitos antes do envio | `SensitiveDataRedactor` |
| IA — saída | Esquema fechado, decodificação estrita, limite de tamanho (64 KB) e de ações (20), sanitização de textos, validação de IDs/horários/durações | `AIProposal.swift` |
| IA — execução | Nada é aplicado sem confirmação; cada ação mapeia para um método conhecido; ações com conflito começam desmarcadas; auditoria em `AIProposalRecord` | `AIProposalExecutor`, `AssistantView` |
| Entradas | Sanitização de títulos/notas (caracteres de controle, tamanho), validação de intervalos | `InputValidator` |
| Logs | `os.Logger` sem dados pessoais (apenas tipos de erro/categorias) | `AppLog` |
| Permissões | Solicitadas apenas por ação da usuária; app funciona com todas negadas; Lembretes não é solicitado | Onboarding, Perfil |
| Calendário externo | Somente leitura por padrão; exclusão externa apenas com confirmação explícita; desativar espelho só desvincula | `EventEditorView` |
| Exclusão de dados | Exclui todos os modelos, Keychain e snapshot de widget; notificações removidas | `DataManagementView`, `deleteAllData` |
| Exportação | JSON completo dos dados do Dayli, arquivo com proteção completa | `DataExporter` |
| Contexto bancário | O app não pede credenciais corporativas nem acessa sistemas; avisos para não registrar dados de clientes | `AreaDetailView`, `PrivacySettingsView` |

## Limitações conhecidas

- **Não compilado/testado** neste ambiente; controles precisam ser verificados em dispositivo.
- A redação por expressões regulares é **heurística**: pode deixar passar dados sensíveis em formatos não previstos e remover números legítimos. É uma camada adicional, não substituta do consentimento e da minimização.
- O assistente local recebe títulos completos (não saem do aparelho).
- Fotos de perfil são guardadas (redimensionadas) no banco local.
- Não há bloqueio por Face ID/código dentro do app (roadmap).
- O backend de IA, autenticação de aparelhos, rate limiting e retenção de dados no servidor estão **fora deste repositório** e precisam de projeto próprio (veja `docs/AI_BACKEND_CONTRACT.md`).
- O manifesto de privacidade (`PrivacyInfo.xcprivacy`) ainda precisa ser criado/validado no Xcode conforme as APIs efetivamente usadas (ex.: `UserDefaults` não é usado; `FileManager` de contêiner é).

## Reportar vulnerabilidades
Defina um canal (e-mail dedicado) antes da publicação.
