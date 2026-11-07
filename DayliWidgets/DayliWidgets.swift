import WidgetKit
import SwiftUI
import UIKit
import DayliCore

// Os widgets leem apenas o snapshot mínimo gravado pelo app no App Group.
// Não acessam o banco nem o EventKit.

private enum WidgetConfig {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "DayliAppGroupIdentifier") as? String ?? "group.app.dayli.shared"
    }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        return WidgetSnapshotStore.read(from: url)
    }
}

private enum WColor {
    static let background = Color(light: 0xF8F5F0, dark: 0x17151B)
    static let text = Color(light: 0x35313C, dark: 0xF3F0EB)
    static let secondary = Color(light: 0x6F6A78, dark: 0xB5AFBC)
    static let lavender = Color(rgb: 0xB8A3CE)
    static let sage = Color(rgb: 0xA3B8A6)
    static let muted = Color(light: 0xF0EDE9, dark: 0x2C2832)

    static func hex(_ string: String?) -> Color {
        guard var s = string else { return lavender }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return lavender }
        return Color(rgb: value)
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        })
    }
}

private func timeString(_ date: Date?) -> String {
    guard let date else { return "" }
    return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "pt_BR")))
}

// MARK: - Timeline

struct DayliWidgetEntry: WidgetKit.TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// O snapshot é do dia corrente?
    var isCurrent: Bool {
        guard let snapshot else { return false }
        return Calendar.current.isDate(snapshot.day, inSameDayAs: date)
    }
}

struct DayliProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayliWidgetEntry {
        DayliWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayliWidgetEntry) -> Void) {
        completion(DayliWidgetEntry(date: .now, snapshot: WidgetConfig.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayliWidgetEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetConfig.loadSnapshot()
        // Uma entrada agora e outra a cada início/fim de evento, para "próximo compromisso" avançar sozinho.
        var dates = [now]
        dates += (snapshot?.transitionDates(after: now) ?? []).prefix(12)
        let entries = dates.map { DayliWidgetEntry(date: $0, snapshot: snapshot) }
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 + 60)
        let refresh = min(midnight, now.addingTimeInterval(2 * 3_600))
        completion(Timeline(entries: entries, policy: .after(max(refresh, dates.last ?? now))))
    }
}

// MARK: - Views

struct DayliWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayliWidgetEntry

    var body: some View {
        Group {
            if !entry.isCurrent {
                staleView
            } else if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: small(snapshot)
                case .systemMedium: medium(snapshot)
                case .systemLarge: large(snapshot)
                case .accessoryRectangular: rectangular(snapshot)
                case .accessoryInline: inline(snapshot)
                case .accessoryCircular: circular(snapshot)
                default: small(snapshot)
                }
            }
        }
        .containerBackground(for: .widget) { WColor.background }
    }

    private var staleView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dayli").font(.headline).foregroundStyle(WColor.text)
            Text("Abra o app para atualizar seu dia.").font(.caption).foregroundStyle(WColor.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRÓXIMO").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(WColor.secondary)
            if let next = s.nextEvent(at: entry.date) {
                RoundedRectangle(cornerRadius: 2).fill(WColor.hex(next.colorHex)).frame(width: 24, height: 3)
                Text(s.displayTitle(for: next)).font(.headline).foregroundStyle(WColor.text).lineLimit(3)
                Spacer(minLength: 0)
                Text((next.start ?? entry.date) <= entry.date ? "Agora" : timeString(next.start))
                    .font(.title3.weight(.semibold)).foregroundStyle(WColor.text)
            } else {
                Text("Agenda livre").font(.headline).foregroundStyle(WColor.text)
                Spacer(minLength: 0)
                Text("\(s.progress.pending) tarefa(s) restante(s)").font(.caption).foregroundStyle(WColor.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "pt_BR"))).capitalized)
                    .font(.caption).foregroundStyle(WColor.secondary)
                Text(entry.date.formatted(.dateTime.day())).font(.largeTitle.weight(.semibold)).foregroundStyle(WColor.text)
                Spacer(minLength: 0)
                Text("\(s.completedTasks)/\(s.totalTasks) tarefas").font(.caption2).foregroundStyle(WColor.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                let upcoming = s.upcomingEvents(at: entry.date, limit: 2)
                if upcoming.isEmpty {
                    Text("Sem compromissos pela frente").font(.caption).foregroundStyle(WColor.secondary)
                }
                ForEach(upcoming) { item in row(item, s) }
                let tasks = s.priorityTasks.prefix(max(0, 3 - upcoming.count))
                ForEach(Array(tasks)) { item in row(item, s) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))).capitalized)
                    .font(.headline).foregroundStyle(WColor.text)
                Spacer()
                Text("\(s.progress.percent)%").font(.headline).foregroundStyle(WColor.text)
            }
            ProgressView(value: s.progress.fraction).tint(WColor.lavender)
            Text("Agenda").font(.caption.weight(.semibold)).foregroundStyle(WColor.secondary)
            let events = s.upcomingEvents(at: entry.date, limit: 4)
            if events.isEmpty { Text("Nada mais na agenda hoje.").font(.caption).foregroundStyle(WColor.secondary) }
            ForEach(events) { row($0, s) }
            Text("Prioridades").font(.caption.weight(.semibold)).foregroundStyle(WColor.secondary).padding(.top, 4)
            if s.priorityTasks.isEmpty { Text("Tudo em dia. 🌿").font(.caption).foregroundStyle(WColor.secondary) }
            ForEach(s.priorityTasks.prefix(4)) { row($0, s) }
            Spacer(minLength: 0)
        }
    }

    private func row(_ item: WidgetSnapshot.Item, _ s: WidgetSnapshot) -> some View {
        HStack(spacing: 6) {
            if item.isTask {
                Image(systemName: "circle").font(.caption2).foregroundStyle(WColor.hex(item.colorHex))
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(WColor.hex(item.colorHex)).frame(width: 3, height: 14)
            }
            Text(s.displayTitle(for: item)).font(.caption).foregroundStyle(WColor.text).lineLimit(1)
            Spacer(minLength: 0)
            if let start = item.start { Text(timeString(start)).font(.caption2).foregroundStyle(WColor.secondary).monospacedDigit() }
        }
    }

    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let next = s.nextEvent(at: entry.date) {
                Text(timeString(next.start)).font(.caption.weight(.semibold))
                Text(s.displayTitle(for: next)).font(.caption).lineLimit(2)
            } else {
                Text("Dayli").font(.caption.weight(.semibold))
                Text("\(s.progress.pending) tarefa(s) restante(s)").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ s: WidgetSnapshot) -> some View {
        Text("\(s.progress.pending) tarefa(s) restante(s)")
    }

    private func circular(_ s: WidgetSnapshot) -> some View {
        Gauge(value: s.progress.fraction) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(s.progress.pending)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

// MARK: - Widgets

struct DayliTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayliTodayWidget", provider: DayliProvider()) { entry in
            DayliWidgetView(entry: entry)
        }
        .configurationDisplayName("Meu dia")
        .description("Próximos compromissos, tarefas prioritárias e progresso.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DayliLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DayliLockScreenWidget", provider: DayliProvider()) { entry in
            DayliWidgetView(entry: entry)
        }
        .configurationDisplayName("Dayli na tela bloqueada")
        .description("Próximo compromisso e tarefas restantes.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

@main
struct DayliWidgetBundle: WidgetBundle {
    var body: some Widget {
        DayliTodayWidget()
        DayliLockScreenWidget()
    }
}
