import SwiftUI
import DayliCore

/// Folha "Nova atividade" (design Stitch: adicionar_atividade_bottom_sheet).
/// Alterna entre tarefa, compromisso, hábito e meta, reaproveitando os editores completos.
struct QuickAddView: View {
    @State var initialKind: QuickAddKind

    init(initialKind: QuickAddKind) {
        _initialKind = State(initialValue: initialKind)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tipo", selection: $initialKind) {
                ForEach(QuickAddKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DayliSpacing.screenMargin)
            .padding(.top, DayliSpacing.md)
            .padding(.bottom, DayliSpacing.sm)
            .background(DayliColor.background)

            Group {
                switch initialKind {
                case .task: TaskEditorView(task: nil, initialDraft: defaultTaskDraft)
                case .event: EventEditorView(event: nil, initialStart: nextHour)
                case .habit: HabitEditorView(habit: nil)
                case .goal: GoalEditorView(goal: nil)
                }
            }
            .id(initialKind) // recria o editor ao trocar de tipo
        }
        .background(DayliColor.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DayliRadius.sheet)
    }

    private var defaultTaskDraft: TaskDraft {
        var draft = TaskDraft()
        draft.hasDate = true
        draft.dueDate = Calendar.dayli.startOfDay(for: .now)
        return draft
    }

    private var nextHour: Date {
        Calendar.dayli.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
    }
}
