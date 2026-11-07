import Foundation
import os
import SwiftUI

/// Logs sem informações pessoais: nunca registre títulos, notas ou nomes.
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "app.dayli.ios"
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let widgets = Logger(subsystem: subsystem, category: "widgets")
}

enum AppConfig {
    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "DayliAppGroupIdentifier") as? String ?? "group.app.dayli.shared"
    }

    /// URL do backend de IA definida no build (Info.plist). Pode ser sobrescrita no Perfil.
    static var defaultAIBackendURL: String {
        Bundle.main.object(forInfoDictionaryKey: "DayliAIBackendURL") as? String ?? ""
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}

extension Calendar {
    /// Calendário do app: pt-BR, fuso atual do aparelho.
    static var dayli: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale(identifier: "pt_BR")
        return calendar
    }
}

enum DayliFormat {
    static let locale = Locale(identifier: "pt_BR")

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    static func dayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    static func weekdayDayMonth(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized(with: locale)
    }

    static func shortWeekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).locale(locale))
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)min"
        }
    }

    /// "Hoje", "Amanhã", "Ontem" ou data curta.
    static func relativeDay(_ date: Date, calendar: Calendar = .dayli, now: Date = .now) -> String {
        switch calendar.daysBetween(now, date) {
        case 0: return "Hoje"
        case 1: return "Amanhã"
        case -1: return "Ontem"
        default: return dayMonth(date)
        }
    }
}

extension Color {
    /// Cria cor a partir de "#RRGGBB" ou "RRGGBB". Valores inválidos resultam em cinza neutro.
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        guard value.count == 6, Scanner(string: value).scanHexInt64(&rgb) else {
            self = Color(red: 0.6, green: 0.6, blue: 0.6)
            return
        }
        self = Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// Agrupa várias mudanças seguidas em uma única execução (ex.: reprogramar notificações).
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?
    private let delay: Duration

    init(delay: Duration) { self.delay = delay }

    func schedule(_ action: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
