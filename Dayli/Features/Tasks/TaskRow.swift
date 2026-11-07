import SwiftUI
import DayliCore

struct TaskRow: View {
    let task: TaskItem
    var onToggle: () -> Void
    var onOpen: () -> Void
    var onToggleSubtask: (Subtask) -> Void = { _ in }

    @State private var showSubtasks = false

    var body: some View {
        let now = Date.now
        let calendar = Calendar.dayli
        let overdue = TaskTiming.isOverdue(dueDate: task.dueDate, hasTime: task.hasTime, isCompleted: task.isCompleted, now: now, calendar: calendar)
        let colorHex = task.category?.colorHex ?? "#A3B8A6"

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                CompletionCircle(isCompleted: task.isCompleted, colorHex: colorHex, action: onToggle)
                    .padding(.leading, -10)
                    .padding(.top, -8)
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if let category = task.category { CategoryChip(category: category) }
                            Spacer(minLength: 0)
                            Text(dueLabel(now: now, calendar: calendar, overdue: overdue))
                                .font(DayliFont.caption)
                                .foregroundStyle(overdue ? DayliColor.gentleWarning : DayliColor.textSecondary)
                        }
                        Text(task.title)
                            .font(DayliFont.bodyLarge.weight(.medium))
                            .foregroundStyle(task.isCompleted ? DayliColor.textSecondary : DayliColor.textPrimary)
                            .strikethrough(task.isCompleted, color: DayliColor.textSecondary)
                            .multilineTextAlignment(.leading)
                        metadata
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if showSubtasks && !task.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.sortedSubtasks) { sub in
                        Button { onToggleSubtask(sub) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(sub.isDone ? Color(hex: colorHex) : DayliColor.divider)
                                Text(sub.title)
                                    .font(DayliFont.bodySmall)
                                    .strikethrough(sub.isDone)
                                    .foregroundStyle(DayliColor.textPrimary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sub.title), \(sub.isDone ? "feita" : "pendente")")
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(14)
        .background(DayliColor.surface, in: RoundedRectangle(cornerRadius: DayliRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DayliRadius.card, style: .continuous).strokeBorder(DayliColor.border, lineWidth: 0.5))
        .opacity(task.isCompleted ? 0.8 : 1)
    }

    @ViewBuilder
    private var metadata: some View {
        let done = task.subtasks.filter(\.isDone).count
        HStack(spacing: 12) {
            if !task.subtasks.isEmpty {
                Button { withAnimation { showSubtasks.toggle() } } label: {
                    Label("\(done)/\(task.subtasks.count) itens", systemImage: "checklist")
                }
                .buttonStyle(.plain)
                .accessibilityHint(showSubtasks ? "Ocultar subtarefas" : "Mostrar subtarefas")
            }
            if task.priority != .medium {
                Label(task.priority.title, systemImage: task.priority == .high ? "flag.fill" : "flag")
            }
            if task.recurrence != nil {
                Image(systemName: "repeat").accessibilityLabel("Recorrente")
            }
            if task.reminderOffsetMinutes != nil {
                Image(systemName: "bell").accessibilityLabel("Com lembrete")
            }
        }
        .font(DayliFont.caption)
        .foregroundStyle(DayliColor.textSecondary)
    }

    private func dueLabel(now: Date, calendar: Calendar, overdue: Bool) -> String {
        if task.isCompleted, let completed = task.completedAt { return "Feito às \(DayliFormat.time(completed))" }
        guard let due = task.dueDate else { return "Sem data" }
        if overdue && !calendar.isDate(due, inSameDayAs: now) {
            return TaskTiming.gentleOverdueLabel(dueDate: due, now: now, calendar: calendar)
        }
        let day = DayliFormat.relativeDay(due, calendar: calendar, now: now)
        return task.hasTime ? "\(day) · \(DayliFormat.time(due))" : day
    }
}
