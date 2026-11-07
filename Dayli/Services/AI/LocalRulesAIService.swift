import Foundation
import DayliCore

/// Assistente local, determinístico, que entende alguns pedidos frequentes em português.
///
/// Não é IA generativa: é claramente identificado na interface como "assistente local".
/// Roda inteiramente no aparelho e produz o mesmo tipo de proposta (`AIProposal`) que o
/// backend, passando pela mesma validação e confirmação.
struct LocalRulesAIService: AIService {
    var kind: AIServiceKind { .localRules }

    func propose(for payload: AIContextPayload) async throws -> AIProposal {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: payload.timeZone) ?? .current
        calendar.locale = Locale(identifier: "pt_BR")
        return Interpreter(payload: payload, calendar: calendar).respond()
    }

    struct Interpreter {
        let payload: AIContextPayload
        let calendar: Calendar

        var text: String {
            payload.userMessage.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        }

        func respond() -> AIProposal {
            let t = text
            if t.contains("quais compromissos") || t.contains("o que tenho") || t.contains("minha agenda") || t.contains("compromissos tenho") {
                return listCommitments()
            }
            if t.contains("estudar") && (t.contains("hora") || t.contains("min")) {
                return scheduleBlock(title: "Estudar", area: .studies)
            }
            if t.contains("academia") || t.contains("treinar") || t.contains("treino") {
                return scheduleWorkouts()
            }
            if t.contains("organiz") || t.contains("distribu") || t.contains("planej") || t.contains("nao consegui") || t.contains("prioridade") {
                return organize()
            }
            return AIProposal(message: """
            Posso ajudar com pedidos como:
            • "Organize meu dia de amanhã"
            • "Preciso estudar duas horas depois do trabalho"
            • "Quero ir à academia três vezes nesta semana"
            • "Quais compromissos tenho na sexta-feira?"
            • "Não consegui terminar minhas tarefas"
            """, actions: [])
        }

        // MARK: Intenções

        private func targetDay() -> Date {
            let today = calendar.startOfDay(for: payload.now)
            let t = text
            if t.contains("depois de amanha") { return calendar.addingDays(2, to: today) }
            if t.contains("amanha") || t.contains("nao consegui") { return calendar.addingDays(1, to: today) }
            let names: [(String, Int)] = [("domingo", 1), ("segunda", 2), ("terca", 3), ("quarta", 4), ("quinta", 5), ("sexta", 6), ("sabado", 7)]
            if let match = names.first(where: { t.contains($0.0) }) {
                for offset in 0..<7 {
                    let day = calendar.addingDays(offset, to: today)
                    if calendar.component(.weekday, from: day) == match.1 { return day }
                }
            }
            return today
        }

        private func busyIntervals() -> [BusyInterval] {
            payload.busy.enumerated().compactMap { BusyInterval(id: "busy:\($0.offset)", title: $0.element.label, start: $0.element.start, end: $0.element.end) }
        }

        private func listCommitments() -> AIProposal {
            let day = targetDay()
            let interval = calendar.dayInterval(for: day)
            let items = payload.busy.filter { $0.start < interval.end && $0.end > interval.start }.sorted { $0.start < $1.start }
            let dayName = DayliFormat.weekdayDayMonth(day)
            guard !items.isEmpty else {
                return AIProposal(message: "Você não tem compromissos registrados para \(dayName). 🌿", actions: [])
            }
            let lines = items.map { "• \(DayliFormat.time($0.start))–\(DayliFormat.time($0.end)) \($0.label)" }.joined(separator: "\n")
            return AIProposal(message: "Para \(dayName):\n\(lines)", actions: [])
        }

        private func organize() -> AIProposal {
            let day = targetDay()
            let dayEnd = calendar.endOfDay(for: day)
            let candidates = payload.tasks.filter { !$0.hasTime && ($0.dueDate.map { $0 < dayEnd } ?? ($0.priority == .high)) }
            guard !candidates.isEmpty else {
                return AIProposal(message: "Não encontrei tarefas pendentes sem horário para organizar. Seu dia parece tranquilo. ☀️", actions: [])
            }
            let plan = DayPlanner(calendar: calendar).plan(
                day: day,
                tasks: candidates.map { PlannableTask(id: $0.id, title: $0.title, priority: $0.priority, dueDate: $0.dueDate, estimatedMinutes: $0.durationMinutes, area: $0.area) },
                busy: busyIntervals(), routine: payload.routine, now: payload.now)
            let actions = plan.suggestions.map {
                AIAction(type: .rescheduleTask, taskID: $0.taskID, title: $0.title, start: $0.start,
                         durationMinutes: Int($0.end.timeIntervalSince($0.start) / 60), rationale: $0.reason)
            }
            var message = "Preparei uma sugestão para \(DayliFormat.weekdayDayMonth(day)), respeitando seus compromissos e pausas."
            if !plan.unplanned.isEmpty {
                message += " \(plan.unplanned.count) \(plan.unplanned.count == 1 ? "tarefa ficou" : "tarefas ficaram") de fora para não sobrecarregar seu dia."
            }
            return AIProposal(message: message, actions: actions)
        }

        private func requestedMinutes() -> Int {
            let t = text
            let words: [String: Int] = ["uma": 1, "um": 1, "duas": 2, "dois": 2, "tres": 3, "quatro": 4, "cinco": 5, "meia": 0]
            let tokens = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            for (index, token) in tokens.enumerated() {
                let value = Int(token) ?? words[token]
                guard let value, index + 1 < tokens.count else { continue }
                let unit = tokens[index + 1]
                if unit.hasPrefix("hora") { return value * 60 }
                if unit.hasPrefix("min") { return value }
            }
            return 60
        }

        private func scheduleBlock(title: String, area: LifeArea) -> AIProposal {
            let minutes = min(max(requestedMinutes(), 15), 6 * 60)
            let day = targetDay()
            let task = PlannableTask(id: UUID(), title: title, priority: .medium, dueDate: day, estimatedMinutes: minutes, area: area)
            var routine = payload.routine
            routine.maxPersonalFocusMinutes = max(routine.maxPersonalFocusMinutes, minutes)
            let plan = DayPlanner(calendar: calendar).plan(day: day, tasks: [task], busy: busyIntervals(), routine: routine, now: payload.now)
            guard let slot = plan.suggestions.first else {
                return AIProposal(message: "Não encontrei \(DayliFormat.duration(minutes: minutes)) livres nesse dia. Quer tentar outro dia?", actions: [])
            }
            return AIProposal(message: "Encontrei um horário livre para \(title.lowercased()):",
                              actions: [AIAction(type: .createTask, title: title, start: slot.start, durationMinutes: minutes,
                                                 priority: .medium, categoryName: area == .studies ? "Estudos" : nil,
                                                 rationale: "Horário livre após seus compromissos.")])
        }

        private func scheduleWorkouts() -> AIProposal {
            let t = text
            let words: [String: Int] = ["uma": 1, "duas": 2, "tres": 3, "quatro": 4, "cinco": 5]
            let tokens = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            var times = 3
            if let index = tokens.firstIndex(where: { $0.hasPrefix("vez") }), index > 0 {
                times = Int(tokens[index - 1]) ?? words[tokens[index - 1]] ?? 3
            }
            times = min(max(times, 1), 6)

            let today = calendar.startOfDay(for: payload.now)
            let weekEnd = calendar.dateInterval(of: .weekOfYear, for: today)?.end ?? calendar.addingDays(7, to: today)
            var actions: [AIAction] = []
            var day = today
            var busy = busyIntervals()
            // Distribui com pelo menos um dia de intervalo quando possível.
            while day < weekEnd && actions.count < times {
                let task = PlannableTask(id: UUID(), title: "Academia", priority: .medium, dueDate: day, estimatedMinutes: 60, area: .fitness)
                if let slot = DayPlanner(calendar: calendar).plan(day: day, tasks: [task], busy: busy, routine: payload.routine, now: payload.now).suggestions.first {
                    actions.append(AIAction(type: .createTask, title: "Academia", start: slot.start, durationMinutes: 60, priority: .medium,
                                            categoryName: "Academia", rationale: "Fora do horário de trabalho, com folga."))
                    if let b = BusyInterval(id: "new:\(actions.count)", title: "Academia", start: slot.start, end: slot.end) { busy.append(b) }
                    day = calendar.addingDays(2, to: day)
                } else {
                    day = calendar.addingDays(1, to: day)
                }
            }
            if actions.isEmpty {
                return AIProposal(message: "Não encontrei horários livres para treinar no restante desta semana. Que tal planejar a próxima?", actions: [])
            }
            let note = actions.count < times ? " Encontrei espaço para \(actions.count) de \(times) treinos no restante da semana." : ""
            return AIProposal(message: "Sugestão de treinos para esta semana.\(note)", actions: actions)
        }
    }
}
