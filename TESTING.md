# Testes

> Nenhum teste foi executado ainda: o ambiente de desenvolvimento atual (Windows) não tem Swift/Xcode. Os resultados reais devem ser registrados em [PROGRESS.md](PROGRESS.md) após a primeira execução.

## Camadas

| Camada | Alvo | Como rodar | O que cobre |
|---|---|---|---|
| Regras puras | `Packages/DayliCore/Tests` (XCTest) | `cd Packages/DayliCore && swift test` | Recorrência (diária, semanal com dias, quinzenal, mensal em meses curtos, término, DST), tarefas recorrentes (só a próxima ocorrência, recuperação de atrasos), conflitos, janelas livres, planejador (ocupados, prioridades, trabalho × pessoal, passado, limite diário, dia cheio, sono após meia-noite, DST, 500 tarefas), linha do tempo (dedupe), progresso (ignora eventos), hábitos (sequência diária/dias/semanal, meta quantitativa, consistência), metas (manual, etapas, hábito vinculado), filtros e rótulos de tarefas, sanitização, saudação, IA (JSON válido/inválido/tipos errados/versão/tamanho/ações demais, validação de IDs/horário/duração/horizonte, conflitos, sanitização), redação de dados sensíveis, minimização de contexto, notificações (silêncio, dedupe, limite), snapshot de widget |
| Integração | `DayliTests` | ⌘U no Xcode ou `xcodebuild test` | Repositório com SwiftData em memória: criar/editar/excluir (cascata), título inválido, concluir/reabrir, recorrência sem duplicar, reagendar/duplicar, tarefas do dia, exclusão de categoria preserva tarefas, idempotência, eventos (validação, conflitos, recorrência), hábitos (registro, toggle, futuro bloqueado), metas (vínculo explícito, etapas), onboarding + exclusão total, 1.000 tarefas; IA: resposta inválida não altera dados, só ações confirmadas são aplicadas, executor ignora tarefas concluídas/inexistentes, assistente local não altera dados, HTTPS obrigatório, calendário sem permissão |
| Interface | `DayliUITests` | ⌘U | Onboarding → Hoje com nome; adicionar tarefa rápida e concluir na tela Hoje; abrir "Organizar meu dia" |

O argumento `-uitesting` faz o app usar banco em memória.

## Checklist manual (dispositivo)
- [ ] Onboarding com e sem permissões; pular.
- [ ] Fechar e reabrir: dados preservados.
- [ ] Negar e depois revogar Calendário em Ajustes: app continua funcionando, mensagens corretas.
- [ ] Acesso "somente adicionar eventos" (write-only).
- [ ] Notificações: agendar tarefa com lembrete, editar e excluir — conferir que não duplica.
- [ ] Horário de silêncio.
- [ ] Widgets em todos os tamanhos e na tela bloqueada, com "ocultar detalhes".
- [ ] Siri: "Adicionar tarefa no Dayli", "Registrar hábito no Dayli".
- [ ] Dynamic Type nos tamanhos de acessibilidade; VoiceOver nas telas Hoje, Tarefas e Agenda.
- [ ] Modo escuro.
- [ ] iPhone SE (tela pequena) e Pro Max.
- [ ] Modo avião: todas as funções exceto IA remota.
- [ ] Instruments: Time Profiler na abertura e rolagem da Agenda (mês) com dados de demonstração; Leaks.
