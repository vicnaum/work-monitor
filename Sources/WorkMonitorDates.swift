import Foundation

enum WorkMonitorDates {
    private static let storageLocale = Locale(identifier: "en_US_POSIX")

    // MARK: - Calendars

    static var storageCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = storageLocale
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    static var uiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    // MARK: - Cached formatters (storage — locale-insensitive, safe to cache)

    private static let _storageDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = storageCalendar
        f.locale = storageLocale
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let _timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - Storage formatting

    static func storageDayString(for date: Date) -> String {
        _storageDayFormatter.timeZone = .autoupdatingCurrent
        return _storageDayFormatter.string(from: date)
    }

    static func date(fromStorageDayString value: String) -> Date? {
        _storageDayFormatter.timeZone = .autoupdatingCurrent
        return _storageDayFormatter.date(from: value)
    }

    // MARK: - UI formatting (recreated to respect locale changes)

    static func mediumDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = uiCalendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    static func fullDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = uiCalendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    static func timeString(for date: Date) -> String {
        _timeFormatter.timeZone = .autoupdatingCurrent
        return _timeFormatter.string(from: date)
    }

    static func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = uiCalendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: startOfMonth(for: date))
    }

    static func orderedWeekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = uiCalendar
        formatter.locale = .autoupdatingCurrent
        let symbols = formatter.shortStandaloneWeekdaySymbols
            ?? formatter.shortWeekdaySymbols
            ?? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let startIndex = max(uiCalendar.firstWeekday - 1, 0)
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    // MARK: - Calendar math

    static func startOfMonth(for date: Date) -> Date {
        uiCalendar.date(from: uiCalendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func daysInMonth(for date: Date) -> [Date?] {
        let monthStart = startOfMonth(for: date)
        guard let range = uiCalendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }

        let weekday = uiCalendar.component(.weekday, from: monthStart)
        let leadingBlanks = (weekday - uiCalendar.firstWeekday + 7) % 7
        let blanks = Array<Date?>(repeating: nil, count: leadingBlanks)
        let days = range.compactMap { day in
            uiCalendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }

        return blanks + days
    }

    static func canNavigateForward(from displayedMonth: Date, now: Date = Date()) -> Bool {
        guard let nextMonth = uiCalendar.date(byAdding: .month, value: 1, to: startOfMonth(for: displayedMonth)) else {
            return false
        }

        let currentMonth = startOfMonth(for: now)
        return uiCalendar.compare(nextMonth, to: currentMonth, toGranularity: .month) != .orderedDescending
    }

    static func isFutureDay(_ date: Date, now: Date = Date()) -> Bool {
        uiCalendar.startOfDay(for: date) > uiCalendar.startOfDay(for: now)
    }
}
