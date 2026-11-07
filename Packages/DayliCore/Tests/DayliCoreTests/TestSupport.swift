import Foundation
@testable import DayliCore

enum TestCalendar {
    static func make(_ identifier: String = "America/Sao_Paulo") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        calendar.locale = Locale(identifier: "pt_BR")
        calendar.firstWeekday = 1
        return calendar
    }
}

extension Calendar {
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
