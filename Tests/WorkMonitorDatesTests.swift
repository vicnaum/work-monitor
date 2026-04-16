import XCTest
@testable import WorkMonitorLib

final class WorkMonitorDatesTests: XCTestCase {

    // MARK: - Storage day string

    func testStorageDayStringFormat() {
        let date = Date()
        let result = WorkMonitorDates.storageDayString(for: date)
        // yyyy-MM-dd = 10 chars, two dashes
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.filter({ $0 == "-" }).count, 2)
    }

    func testStorageDayStringRoundTrip() {
        let original = Date()
        let dayString = WorkMonitorDates.storageDayString(for: original)
        let parsed = WorkMonitorDates.date(fromStorageDayString: dayString)
        XCTAssertNotNil(parsed)

        let cal = WorkMonitorDates.storageCalendar
        XCTAssertEqual(cal.component(.year, from: original),
                       cal.component(.year, from: parsed!))
        XCTAssertEqual(cal.component(.month, from: original),
                       cal.component(.month, from: parsed!))
        XCTAssertEqual(cal.component(.day, from: original),
                       cal.component(.day, from: parsed!))
    }

    func testInvalidStorageDayString() {
        XCTAssertNil(WorkMonitorDates.date(fromStorageDayString: "not-a-date"))
        XCTAssertNil(WorkMonitorDates.date(fromStorageDayString: ""))
        XCTAssertNil(WorkMonitorDates.date(fromStorageDayString: "April 15, 2026"))
    }

    // MARK: - Time string

    func testTimeStringFormat() {
        let date = Date()
        let result = WorkMonitorDates.timeString(for: date)
        // HH:mm = 5 chars, one colon
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.contains(":"))
    }

    // MARK: - Start of month

    func testStartOfMonth() {
        guard let date = WorkMonitorDates.date(fromStorageDayString: "2026-04-15") else {
            XCTFail("Could not parse date")
            return
        }
        let start = WorkMonitorDates.startOfMonth(for: date)
        let cal = WorkMonitorDates.uiCalendar
        XCTAssertEqual(cal.component(.day, from: start), 1)
        XCTAssertEqual(cal.component(.month, from: start), 4)
        XCTAssertEqual(cal.component(.year, from: start), 2026)
    }

    func testStartOfMonthOnFirstDay() {
        guard let date = WorkMonitorDates.date(fromStorageDayString: "2026-01-01") else {
            XCTFail("Could not parse date")
            return
        }
        let start = WorkMonitorDates.startOfMonth(for: date)
        let cal = WorkMonitorDates.uiCalendar
        XCTAssertEqual(cal.component(.day, from: start), 1)
        XCTAssertEqual(cal.component(.month, from: start), 1)
    }

    // MARK: - Days in month

    func testDaysInMonthApril2026() {
        guard let date = WorkMonitorDates.date(fromStorageDayString: "2026-04-15") else {
            XCTFail("Could not parse date")
            return
        }
        let days = WorkMonitorDates.daysInMonth(for: date)
        let nonNilDays = days.compactMap { $0 }
        XCTAssertEqual(nonNilDays.count, 30, "April has 30 days")

        // April 1, 2026 is a Wednesday. Monday-first: Mon=0, Tue=1, Wed=2 -> 2 blanks
        let leadingBlanks = days.prefix(while: { $0 == nil }).count
        XCTAssertEqual(leadingBlanks, 2, "April 2026 starts on Wednesday, expect 2 leading blanks")
    }

    func testDaysInMonthFebruaryLeapYear() {
        guard let date = WorkMonitorDates.date(fromStorageDayString: "2028-02-10") else {
            XCTFail("Could not parse date")
            return
        }
        let days = WorkMonitorDates.daysInMonth(for: date)
        let nonNilDays = days.compactMap { $0 }
        XCTAssertEqual(nonNilDays.count, 29)
    }

    func testDaysInMonthFebruaryNonLeapYear() {
        guard let date = WorkMonitorDates.date(fromStorageDayString: "2027-02-10") else {
            XCTFail("Could not parse date")
            return
        }
        let days = WorkMonitorDates.daysInMonth(for: date)
        let nonNilDays = days.compactMap { $0 }
        XCTAssertEqual(nonNilDays.count, 28)
    }

    // MARK: - Future day

    func testIsFutureDayTomorrow() {
        let cal = WorkMonitorDates.uiCalendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(WorkMonitorDates.isFutureDay(tomorrow))
    }

    func testIsFutureDayToday() {
        XCTAssertFalse(WorkMonitorDates.isFutureDay(Date()))
    }

    func testIsFutureDayYesterday() {
        let cal = WorkMonitorDates.uiCalendar
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertFalse(WorkMonitorDates.isFutureDay(yesterday))
    }

    func testIsFutureDayWithExplicitNow() {
        guard let jan1 = WorkMonitorDates.date(fromStorageDayString: "2026-01-01"),
              let jan2 = WorkMonitorDates.date(fromStorageDayString: "2026-01-02"),
              let dec31 = WorkMonitorDates.date(fromStorageDayString: "2025-12-31") else {
            XCTFail("Could not parse dates")
            return
        }
        XCTAssertTrue(WorkMonitorDates.isFutureDay(jan2, now: jan1))
        XCTAssertFalse(WorkMonitorDates.isFutureDay(dec31, now: jan1))
        XCTAssertFalse(WorkMonitorDates.isFutureDay(jan1, now: jan1))
    }

    // MARK: - Can navigate forward

    func testCanNavigateForwardSameMonth() {
        let now = Date()
        let thisMonth = WorkMonitorDates.startOfMonth(for: now)
        XCTAssertFalse(WorkMonitorDates.canNavigateForward(from: thisMonth, now: now))
    }

    func testCanNavigateForwardPastMonth() {
        let cal = WorkMonitorDates.uiCalendar
        let now = Date()
        let twoMonthsAgo = cal.date(byAdding: .month, value: -2, to: now)!
        XCTAssertTrue(WorkMonitorDates.canNavigateForward(from: twoMonthsAgo, now: now))
    }

    func testCanNavigateForwardLastMonth() {
        let cal = WorkMonitorDates.uiCalendar
        let now = Date()
        let lastMonth = cal.date(byAdding: .month, value: -1, to: now)!
        XCTAssertTrue(WorkMonitorDates.canNavigateForward(from: lastMonth, now: now))
    }

    func testCanNavigateForwardAcrossYearBoundary() {
        guard let dec2025 = WorkMonitorDates.date(fromStorageDayString: "2025-12-01"),
              let jan2026 = WorkMonitorDates.date(fromStorageDayString: "2026-01-15") else {
            XCTFail("Could not parse dates")
            return
        }
        XCTAssertTrue(WorkMonitorDates.canNavigateForward(from: dec2025, now: jan2026))
    }

    // MARK: - Weekday symbols

    func testOrderedWeekdaySymbolsCount() {
        let symbols = WorkMonitorDates.orderedWeekdaySymbols()
        XCTAssertEqual(symbols.count, 7)
    }

    func testCalendarFirstWeekdayIsMonday() {
        XCTAssertEqual(WorkMonitorDates.uiCalendar.firstWeekday, 2)
    }
}
