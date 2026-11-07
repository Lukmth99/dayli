import SwiftUI
import UIKit
import DayliCore

/// Tokens semânticos derivados do design system exportado do Stitch (DESIGN.md).
/// Cada cor tem variante para o modo escuro.
enum DayliColor {
    private static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    // Base
    static let background = dynamic("#F8F5F0", "#17151B")
    static let surface = dynamic("#FFFFFF", "#221F27")
    static let surfaceMuted = dynamic("#F0EDE9", "#2C2832")
    static let border = dynamic("#EFECE6", "#37323E")
    static let divider = dynamic("#E8E4DC", "#332F39")
    static let textPrimary = dynamic("#35313C", "#F3F0EB")
    static let textSecondary = dynamic("#6F6A78", "#B5AFBC") // levemente mais escuro que #7D7886 para contraste AA
    static let primary = dynamic("#35313C", "#E7E0EE")
    static let onPrimary = dynamic("#FFFFFF", "#201C26")

    // Acentos (áreas da vida)
    static let lavender = Color(hex: "#B8A3CE")
    static let rose = Color(hex: "#D69EAA")
    static let sage = Color(hex: "#A3B8A6")
    static let softBlue = Color(hex: "#9BB8CD")
    static let peach = Color(hex: "#F2C4B7")

    // Tons de texto de alto contraste para usar sobre fundos de acento
    static let lavenderInk = dynamic("#6B5283", "#D4BEEA")
    static let roseInk = dynamic("#8E4A58", "#F0B9C4")
    static let sageInk = dynamic("#4E6652", "#B7CCB9")
    static let blueInk = dynamic("#3E6680", "#B5D0E3")

    static let gentleWarning = dynamic("#A0614F", "#F2C4B7")
    static let destructive = dynamic("#B3261E", "#FFB4AB")

    /// Tom de texto legível para uma cor de categoria.
    static func ink(for hex: String) -> Color {
        switch hex.uppercased() {
        case "#B8A3CE": return lavenderInk
        case "#D69EAA", "#EDC3CC": return roseInk
        case "#A3B8A6": return sageInk
        case "#9BB8CD": return blueInk
        case "#F2C4B7": return gentleWarning
        default: return textPrimary
        }
    }

    /// Paleta oferecida ao criar categorias e hábitos.
    static let palette = ["#9BB8CD", "#B8A3CE", "#A3B8A6", "#D69EAA", "#F2C4B7", "#EDC3CC", "#C9B79C", "#8FA9A3"]
}

enum DayliSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let screenMargin: CGFloat = 20
}

enum DayliRadius {
    static let card: CGFloat = 22
    static let input: CGFloat = 14
    static let button: CGFloat = 16
    static let sheet: CGFloat = 28
}

/// Tipografia baseada em estilos de texto do sistema → suporta Dynamic Type.
/// (A fonte Inter do protótipo não foi embarcada; SF Pro mantém a escala e o tom do design.)
enum DayliFont {
    static let display = Font.system(.largeTitle, design: .default).weight(.bold)
    static let headlineLarge = Font.system(.title, design: .default).weight(.semibold)
    static let headlineMedium = Font.system(.title3, design: .default).weight(.semibold)
    static let headlineSmall = Font.system(.headline, design: .default)
    static let bodyLarge = Font.system(.body)
    static let bodyMedium = Font.system(.subheadline)
    static let bodySmall = Font.system(.footnote)
    static let label = Font.system(.footnote).weight(.medium)
    static let caption = Font.system(.caption2).weight(.medium)
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
