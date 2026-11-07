# Roadmap

## Imediato (bloqueante)
1. Compilar no Mac, corrigir erros de compilação e rodar todos os testes (ver PROGRESS.md).
2. Ícone do app (AppIcon 1024 px) e `PrivacyInfo.xcprivacy`.
3. Validar em dispositivo o checklist manual de TESTING.md.

## Curto prazo
- Ações nas notificações (concluir tarefa, registrar hábito, adiar).
- Widgets interativos (iOS 17 `Button(intent:)`) para concluir tarefas e registrar hábitos.
- Modelos dedicados para Estudos (matérias, sessões com duração, provas) e Datas especiais (aniversários com lembrete anual).
- Duração real de sessões de estudo alimentando metas ("Estudar 20 horas").
- Importação do app Lembretes (EventKit `.reminder`) com permissão própria.
- Extrair textos para String Catalog (preparar outros idiomas).
- Bloqueio do app com Face ID.

## Médio prazo
- Backend da Dayli AI (contrato em docs/AI_BACKEND_CONTRACT.md): autenticação de aparelho (App Attest), rate limiting, retenção zero, logs sem conteúdo.
- Apple Intelligence / Foundation Models on-device (quando disponível no deployment target) como alternativa ao backend.
- Sincronização opcional via CloudKit (exige revisar `@Attribute(.unique)` e opcionalidade dos modelos).
- Live Activities para o compromisso em andamento (há design no Stitch).
- iPad e Apple Watch.
- Migração para Swift 6 (concorrência estrita).
- `#Index` quando o deployment target for iOS 18.
