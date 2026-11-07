# Funcionalidades e estado

Legenda: ✅ implementado (código escrito) · 🟡 parcial · ⏳ pendente · 🔎 aguardando validação em Mac

> Nenhum item foi compilado ou executado ainda (ambiente sem Xcode). Todos os ✅ estão, portanto, também 🔎 até a primeira compilação.

## Fundação
| Item | Estado | Onde |
|---|---|---|
| Projeto Xcode (XcodeGen), app + widgets + testes | ✅ | `project.yml` |
| Núcleo de regras testável | ✅ | `Packages/DayliCore` |
| Design system (tokens, claro/escuro, componentes) | ✅ | `Core/DesignSystem` |
| Persistência SwiftData versionada | ✅ | `Data/Persistence` |
| 5 abas + adição rápida + folhas globais | ✅ | `App/RootView.swift` |
| Tela de erro se o banco não abrir (sem apagar dados) | ✅ | `App/DayliApp.swift` |

## Onboarding (4 etapas)
✅ Boas-vindas com nome opcional · ✅ áreas da vida · ✅ rotina (sono, trabalho, dias, preferências) · ✅ permissões contextuais (notificações, calendário) · ✅ pular · ✅ estado persistido.
🟡 Lembretes (app Lembretes) apenas explicado — não solicitado nem importado (menor privilégio).

## Hoje
✅ Saudação por horário + nome configurável + data + mensagem diária · ✅ avatar/iniciais · ✅ resumo (total, concluídas, pendentes, compromissos, próximo compromisso, progresso só de tarefas) · ✅ linha do tempo combinada (tarefas com horário, compromissos, eventos externos sem duplicar espelhos) · ✅ "Ao longo do dia" para tarefas sem horário · ✅ concluir na própria tela · ✅ ações rápidas · ✅ "Organizar meu dia" · ✅ estado vazio.

## Agenda
✅ Dia / Semana / Mês · ✅ navegação entre datas e "voltar para hoje" · ✅ indicador "Agora" · ✅ criar/editar/excluir compromisso · ✅ início/fim, dia todo, local, descrição, categoria · ✅ recorrência (diária/semanal com dias/mensal/anual, intervalo, término) · ✅ alertas · ✅ conflitos (no editor e no dia) · ✅ filtro por categoria e por eventos externos.
EventKit: ✅ permissão sob demanda · ✅ estados negado/revogado/restrito/somente escrita · ✅ eventos externos ao vivo com origem · ✅ escolher calendários visíveis · ✅ espelhar compromissos em calendário escolhido · ✅ dedupe espelho × externo · ✅ exclusão externa só com confirmação explícita · 🟡 edição de eventos externos é delegada ao app Calendário (somente leitura no Dayli).

## Tarefas
✅ Filtros Hoje / Próximos dias / Esta semana / Mais adiante / Sem data / Concluídas · ✅ todos os campos do escopo · ✅ prioridades · ✅ criar, editar, excluir (com confirmação), concluir, reabrir, duplicar, reagendar (rápido e por data), pesquisar, filtrar (categoria, prioridade), ordenar, subtarefas, mover de categoria · ✅ recorrência por ocorrência · ✅ pendências com rótulos gentis · ✅ barra de adição rápida.

## Minha Vida
✅ Cartões por área (pendentes, feitas na semana, compromissos em 7 dias) · ✅ detalhe da área (pendências, compromissos, metas, hábitos) · ✅ aviso para não registrar dados confidenciais do banco · ✅ aviso de que não há orientação médica.
🟡 Estudos: matérias/sessões/provas são representadas por tarefas, compromissos, hábitos e metas da categoria Estudos; não há modelo dedicado de "matéria" ou "sessão de estudo" ainda.
🟡 Aniversários/datas especiais: via compromissos anuais recorrentes; sem tipo dedicado.

## Hábitos
✅ Cadastro, edição, arquivamento, exclusão · ✅ diária / dias específicos / N vezes por semana · ✅ meta quantitativa com unidade · ✅ registro e desfazer · ✅ histórico em grade de 12 semanas (editável para dias passados) · ✅ sequência que respeita a programação · ✅ consistência 30 dias · ✅ lembretes.

## Metas
✅ Todos os campos · ✅ progresso manual, por etapas ou por hábito vinculado (vínculo explícito; tarefas nunca contam automaticamente) · ✅ conclusão automática ao atingir 100% · ✅ pausar/retomar/arquivar.

## Organizar meu dia
✅ Planejador determinístico offline · ✅ prévia com aprovar/rejeitar/ajustar horário de cada sugestão (com aviso de conflito ao ajustar) · ✅ itens não encaixados com motivo · ✅ conflitos existentes · ✅ nunca move compromissos · ✅ DST/fuso.

## Assistente (Dayli AI)
✅ Protocolo `AIService` · ✅ assistente local identificado ("regras, sem IA generativa") · ✅ cliente remoto HTTPS com token no Keychain · ✅ indisponibilidade tratada sem afetar o app · ✅ consentimento explícito e revogável · ✅ minimização + redação de dados sensíveis · ✅ esquema tipado, decodificação estrita, validação · ✅ prévia + confirmação + execução + resultado + registro auditável.
⏳ Backend (fora deste repositório) — contrato em `docs/AI_BACKEND_CONTRACT.md`.
⏳ Emissão do token de sessão do aparelho (depende do backend).

## Notificações
✅ Tarefas, compromissos, hábitos, resumo matinal, revisão noturna, aviso de prazo · ✅ horários, antecedência, categorias silenciadas, ativação individual, horário de silêncio · ✅ sem duplicidade · ✅ reprogramação a cada mudança · ✅ limite do iOS · ✅ permissão negada · ✅ texto honesto sobre atrasos do iOS.
🟡 Ações interativas na notificação (concluir pela notificação) — roadmap.

## Widgets
✅ Pequeno (próximo compromisso) · ✅ médio (data, próximos, prioridades) · ✅ grande (resumo, agenda, progresso) · ✅ tela bloqueada (retangular, inline, circular) · ✅ App Group + snapshot mínimo · ✅ opção de ocultar títulos · ✅ linha do tempo que avança nos inícios/fins de evento · ✅ estado "abra o app" quando o snapshot é de outro dia.
🟡 Eventos do Calendário Apple aparecem no widget somente se o app os carregou ao gerar o snapshot.

## Siri e Atalhos
✅ Adicionar tarefa · ✅ próxima atividade · ✅ abrir agenda de hoje · ✅ registrar hábito (entidade com sugestões) · ✅ abrir "Organizar meu dia". Nenhuma intenção exclui dados.

## Revisões
✅ Hoje / Semana · ✅ tarefas concluídas, pendentes, compromissos realizados (separados de tarefas), hábitos registrados, metas, reagendadas · ✅ gráfico Swift Charts · ✅ planejar amanhã.

## Perfil e configurações
✅ Nome, foto (redimensionada), aparência, idioma (pt-BR), rotina, áreas, categorias (criar/editar/excluir/reordenar), notificações, calendário, privacidade, IA, exportação JSON, modo demonstração identificado e removível, exclusão total, sobre.
🟡 Idioma: somente pt-BR nesta versão (strings ainda não extraídas para String Catalog).

## Offline
✅ Tudo exceto a IA remota funciona offline (dados locais, planejador e assistente locais, notificações locais).
