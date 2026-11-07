import SwiftUI
import DayliCore

/// Linha da linha do tempo (tela Hoje e Agenda).
struct TimelineRow: View {
    let entry: TimelineEntry
    let category: LifeCategory?
    let now: Date
    var onToggle: () -> Void = {}
    var onOpen: () -> Void = {}

    private var isNow: Bool {
        guard let end = entry.end, !entry.isAllDay else { return false }
        return entry.start <= now && now < end
    }

    private var colorHex: String { category?.colorHex ?? (entry.kind == .externalEvent ? "#9BB8CD" : "#B8A3CE") }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if entry.isCompletable {
                CompletionCircle(isCompleted: entry.isCompleted, colorHex: colorHex, action: onToggle)
                    .padding(.leading, -8)
            } else {
                Image(systemName: entry.kind == .externalEvent ? "calendar" : "calendar.circle")
                    .foregroundStyle(Color(hex: colorHex))
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(timeLabel)
                            .font(DayliFont.caption)
                            .foregroundStyle(isNow ? DayliColor.lavenderInk : DayliColor.textSecondary)
                            .monospacedDigit()
                        if let category {
                            CategoryChip(name: category.name, colorHex: category.colorHex)
                        } else if entry.kind == .externalEvent, let source = entry.sourceName {
                            InfoPill(text: source, systemImage: "calendar")
                        }
                        if let priority = entry.priority, priority == .high, !entry.isCompleted {
                            Image(systemName: "flag.fill")
                                .imageScale(.small)
                                .foregroundStyle(DayliColor.roseInk)
                                .accessibilityLabel("Prioridade alta")
                        }
                    }
                    Text(entry.title)
                        .font(DayliFont.bodyLarge.weight(.medium))
                        .foregroundStyle(entry.isCompleted ? DayliColor.textSecondary : DayliColor.textPrimary)
                        .strikethrough(entry.isCompleted, color: DayliColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isNow {
                InfoPill(text: "Agora")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(DayliColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            if isNow {
                RoundedRectangle(cornerRadius: 2).fill(DayliColor.lavender).frame(width: 3).padding(.vertical, 10)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DayliColor.border, lineWidth: 0.5))
        .opacity(entry.isCompleted ? 0.75 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var timeLabel: String {
        if entry.isAllDay { return entry.kind == .task ? "Qualquer horário" : "Dia todo" }
        if let end = entry.end {
            let minutes = Int(end.timeIntervalSince(entry.start) / 60)
            return "\(DayliFormat.time(entry.start)) · \(DayliFormat.duration(minutes: minutes))"
        }
        return DayliFormat.time(entry.start)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        parts.append(entry.kind == .task ? "Tarefa" : "Compromisso")
        parts.append(entry.title)
        parts.append(entry.isAllDay ? (entry.kind == .task ? "sem horário" : "dia todo") : "às \(DayliFormat.time(entry.start))")
        if let category { parts.append(category.name) }
        if entry.kind == .externalEvent { parts.append("do Calendário") }
        if entry.isCompleted { parts.append("concluída") }
        return parts.joined(separator: ", ")
    }
}

/// Detalhes de um evento do Calendário Apple (somente leitura no Dayli).
struct ExternalEventDetailView: View {
    let entry: TimelineEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(entry.title).font(DayliFont.headlineMedium)
                    if entry.isAllDay {
                        LabeledContent("Quando", value: "Dia todo · \(DayliFormat.dayMonth(entry.start))")
                    } else {
                        LabeledContent("Início", value: "\(DayliFormat.dayMonth(entry.start)) · \(DayliFormat.time(entry.start))")
                        if let end = entry.end { LabeledContent("Término", value: DayliFormat.time(end)) }
                    }
                    if let source = entry.sourceName { LabeledContent("Calendário", value: source) }
                }
                Section {
                    Text("Este evento pertence ao app Calendário. O Dayli apenas o exibe e não o altera. Para editá-lo, use o app Calendário.")
                        .font(DayliFont.bodySmall)
                        .foregroundStyle(DayliColor.textSecondary)
                    if let url = URL(string: "calshow:\(entry.start.timeIntervalSinceReferenceDate)") {
                        Link("Abrir no Calendário", destination: url)
                    }
                }
            }
            .navigationTitle("Evento externo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
