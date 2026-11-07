import SwiftUI
import DayliCore

// MARK: - Card

struct DayliCardModifier: ViewModifier {
    var padding: CGFloat = DayliSpacing.md
    var elevated = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DayliColor.surface, in: RoundedRectangle(cornerRadius: DayliRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DayliRadius.card, style: .continuous).strokeBorder(DayliColor.border, lineWidth: 0.5))
            .shadow(color: Color(hex: "#35313C").opacity(elevated ? 0.06 : 0.03), radius: elevated ? 15 : 10, x: 0, y: elevated ? 8 : 4)
    }
}

extension View {
    func dayliCard(padding: CGFloat = DayliSpacing.md, elevated: Bool = false) -> some View {
        modifier(DayliCardModifier(padding: padding, elevated: elevated))
    }

    /// Fundo creme padrão das telas.
    func dayliScreenBackground() -> some View {
        background(DayliColor.background.ignoresSafeArea())
    }
}

// MARK: - Botões

struct DayliPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DayliFont.headlineSmall)
            .foregroundStyle(DayliColor.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(DayliColor.primary.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: DayliRadius.button, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct DayliSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DayliFont.headlineSmall)
            .foregroundStyle(DayliColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(DayliColor.surface, in: RoundedRectangle(cornerRadius: DayliRadius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DayliRadius.button, style: .continuous).strokeBorder(DayliColor.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == DayliPrimaryButtonStyle {
    static var dayliPrimary: DayliPrimaryButtonStyle { DayliPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DayliSecondaryButtonStyle {
    static var dayliSecondary: DayliSecondaryButtonStyle { DayliSecondaryButtonStyle() }
}

// MARK: - Pílula de categoria

struct CategoryChip: View {
    let name: String
    let colorHex: String
    var symbolName: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbolName { Image(systemName: symbolName).imageScale(.small) }
            Text(name).lineLimit(1)
        }
        .font(DayliFont.caption)
        .foregroundStyle(DayliColor.ink(for: colorHex))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(hex: colorHex).opacity(0.18), in: Capsule())
        .accessibilityLabel("Categoria \(name)")
    }
}

extension CategoryChip {
    init(category: LifeCategory) {
        self.init(name: category.name, colorHex: category.colorHex, symbolName: nil)
    }
}

struct InfoPill: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(DayliFont.caption)
        .foregroundStyle(DayliColor.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DayliColor.surfaceMuted, in: Capsule())
    }
}

// MARK: - Círculo de conclusão

struct CompletionCircle: View {
    let isCompleted: Bool
    var colorHex: String = "#A3B8A6"
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.success()
            action()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(isCompleted ? Color.clear : DayliColor.divider, lineWidth: 1.5)
                    .background(Circle().fill(isCompleted ? Color(hex: colorHex) : Color.clear))
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 26, height: 26)
            .frame(width: 44, height: 44) // área de toque mínima
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCompleted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompleted ? "Concluída" : "Não concluída")
        .accessibilityHint(isCompleted ? "Toque duas vezes para reabrir" : "Toque duas vezes para concluir")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Progresso

struct DayliProgressBar: View {
    let value: Double
    var tint: Color = DayliColor.lavender

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DayliColor.surfaceMuted)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: value)
        .accessibilityElement()
        .accessibilityLabel("Progresso")
        .accessibilityValue("\(Int((max(0, min(1, value)) * 100).rounded())) por cento")
    }
}

struct ProgressRing: View {
    let value: Double
    var tint: Color = DayliColor.lavender
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(DayliColor.surfaceMuted, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((max(0, min(1, value)) * 100).rounded()))%")
                .font(DayliFont.caption)
                .foregroundStyle(DayliColor.textPrimary)
                .minimumScaleFactor(0.6)
        }
        .animation(.easeOut(duration: 0.4), value: value)
        .accessibilityElement()
        .accessibilityLabel("Progresso")
        .accessibilityValue("\(Int((max(0, min(1, value)) * 100).rounded())) por cento")
    }
}

// MARK: - Cabeçalhos e estados

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DayliFont.headlineMedium)
                .foregroundStyle(DayliColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing.uppercased())
                    .font(DayliFont.caption)
                    .tracking(0.6)
                    .foregroundStyle(DayliColor.textSecondary)
            }
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DayliSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DayliColor.lavender)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(title)
                .font(DayliFont.headlineSmall)
                .foregroundStyle(DayliColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DayliFont.bodyMedium)
                .foregroundStyle(DayliColor.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.dayliSecondary)
                    .padding(.top, DayliSpacing.sm)
                    .frame(maxWidth: 260)
            }
        }
        .padding(DayliSpacing.lg)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct LoadingStateView: View {
    var message = "Carregando…"
    var body: some View {
        VStack(spacing: DayliSpacing.sm) {
            ProgressView()
            Text(message).font(DayliFont.bodySmall).foregroundStyle(DayliColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(DayliSpacing.lg)
    }
}

struct InlineNotice: View {
    enum Style { case info, warning, error }
    let style: Style
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: DayliSpacing.sm) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(message).font(DayliFont.bodySmall).foregroundStyle(DayliColor.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DayliRadius.input, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch style {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.circle"
        case .error: return "xmark.octagon"
        }
    }

    private var tint: Color {
        switch style {
        case .info: return DayliColor.lavenderInk
        case .warning: return DayliColor.gentleWarning
        case .error: return DayliColor.destructive
        }
    }
}

struct AvatarView: View {
    let initials: String
    var photoData: Data?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(DayliColor.lavenderInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DayliColor.lavender.opacity(0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DayliColor.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Seletor de dias da semana (1 = domingo ... 7 = sábado).
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    Haptics.selection()
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(RecurrenceRule.shortWeekdayName(day).prefix(3).capitalized)
                        .font(DayliFont.caption)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(isOn ? DayliColor.onPrimary : DayliColor.textPrimary)
                        .background(isOn ? DayliColor.primary : DayliColor.surfaceMuted, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.fullName(day))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    static func fullName(_ day: Int) -> String {
        ["Domingo", "Segunda-feira", "Terça-feira", "Quarta-feira", "Quinta-feira", "Sexta-feira", "Sábado"][max(1, min(7, day)) - 1]
    }
}

/// Seletor de horário (sem data) baseado em `TimeOfDay`.
struct TimeOfDayPicker: View {
    let title: String
    @Binding var value: TimeOfDay

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { value.date(on: .now, calendar: .dayli) },
            set: { value = TimeOfDay.from($0, calendar: .dayli) }
        ), displayedComponents: .hourAndMinute)
    }
}

/// Seletor de categoria (inclui "Sem categoria").
struct CategoryPicker: View {
    let categories: [LifeCategory]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Categoria", selection: $selection) {
            Text("Sem categoria").tag(UUID?.none)
            ForEach(categories) { category in
                Label(category.name, systemImage: category.symbolName).tag(UUID?.some(category.id))
            }
        }
    }
}

/// Seletor de cor da paleta do design system.
struct ColorPalettePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(DayliColor.palette, id: \.self) { hex in
                Button {
                    selection = hex
                    Haptics.selection()
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(DayliColor.textPrimary, lineWidth: selection == hex ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cor \(hex)")
                .accessibilityAddTraits(selection == hex ? .isSelected : [])
            }
        }
    }
}
