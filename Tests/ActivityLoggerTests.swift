import XCTest
@testable import WorkMonitorLib

@MainActor
final class ActivityLoggerTests: XCTestCase {

    private var testDir: URL!
    private var logger: ActivityLogger!

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkMonitorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        logger = ActivityLogger(logDirectory: testDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDir)
    }

    // MARK: - Logging

    func testLogCreatesEntry() {
        XCTAssertEqual(logger.todayEntries.count, 0)
        logger.log(activity: "Test task")
        XCTAssertEqual(logger.todayEntries.count, 1)
        XCTAssertEqual(logger.todayEntries.first?.activity, "Test task")
    }

    func testLogMultipleEntries() {
        logger.log(activity: "First")
        logger.log(activity: "Second")
        logger.log(activity: "Third")
        XCTAssertEqual(logger.todayEntries.count, 3)
        // Most recent first
        XCTAssertEqual(logger.todayEntries.first?.activity, "Third")
    }

    func testLogPersistsToFile() {
        logger.log(activity: "Persistent task")

        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let jsonFile = testDir.appendingPathComponent("\(dayString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonFile.path))

        let mdFile = testDir.appendingPathComponent("\(dayString).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mdFile.path))
    }

    func testLoadTodayReadsPersistedEntries() {
        logger.log(activity: "Task A")
        logger.log(activity: "Task B")

        let logger2 = ActivityLogger(logDirectory: testDir)
        XCTAssertEqual(logger2.todayEntries.count, 2)
    }

    func testSetLogDirectoryReloadsEntriesFromNewFolder() throws {
        logger.log(activity: "Original folder")

        let otherDir = testDir.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([LogEntry(activity: "New folder")])
        let dayString = WorkMonitorDates.storageDayString(for: Date())
        try data.write(to: otherDir.appendingPathComponent("\(dayString).json"))

        logger.setLogDirectory(otherDir)

        XCTAssertEqual(logger.logDirectory, otherDir.standardizedFileURL)
        XCTAssertEqual(logger.todayEntries.count, 1)
        XCTAssertEqual(logger.todayEntries.first?.activity, "New folder")
    }

    // MARK: - Deletion

    func testDeleteEntry() {
        logger.log(activity: "Keep this")
        logger.log(activity: "Delete this")
        let toDelete = logger.todayEntries.first! // "Delete this" (most recent)
        logger.deleteEntry(toDelete)
        XCTAssertEqual(logger.todayEntries.count, 1)
        XCTAssertEqual(logger.todayEntries.first?.activity, "Keep this")
    }

    func testDeleteLastEntryRemovesFiles() {
        logger.log(activity: "Only entry")
        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let jsonFile = testDir.appendingPathComponent("\(dayString).json")
        let mdFile = testDir.appendingPathComponent("\(dayString).md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonFile.path))

        logger.deleteEntry(logger.todayEntries.first!)
        XCTAssertEqual(logger.todayEntries.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonFile.path),
                       "JSON file should be removed when all entries deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: mdFile.path),
                       "Markdown file should be removed when all entries deleted")
    }

    func testDeleteLastEntryRemovesFromDatesWithLogs() {
        logger.log(activity: "Temp entry")
        XCTAssertFalse(logger.datesWithLogs.isEmpty)

        logger.deleteEntry(logger.todayEntries.first!)
        XCTAssertTrue(logger.datesWithLogs.isEmpty,
                      "datesWithLogs should not include days with no entries")
    }

    // MARK: - Slack formatting

    func testSlackFormattedWithTimestamps() {
        logger.log(activity: "Did something")
        let result = logger.slackFormatted(
            date: Date(), entries: logger.todayEntries, showTimestamps: true
        )
        XCTAssertTrue(result.contains("*Daily Update"))
        XCTAssertTrue(result.contains("Did something"))
        XCTAssertTrue(result.contains(":"), "Should contain a time with colon")
    }

    func testSlackFormattedWithoutTimestamps() {
        logger.log(activity: "Did something")
        let result = logger.slackFormatted(
            date: Date(), entries: logger.todayEntries, showTimestamps: false
        )
        XCTAssertTrue(result.contains("Did something"))
        // Without timestamps, lines are just "• activity"
        XCTAssertTrue(result.contains("• Did something"))
    }

    func testSlackFormattedEmptyEntries() {
        let result = logger.slackFormatted(
            date: Date(), entries: [], showTimestamps: true
        )
        XCTAssertTrue(result.contains("No entries yet."))
    }

    // MARK: - Date scanning

    func testScanForDatesFindsLoggedDays() {
        logger.log(activity: "Today's task")
        logger.scanForDates()
        XCTAssertEqual(logger.datesWithLogs.count, 1)
    }

    func testScanForDatesIgnoresEmptyFiles() throws {
        let emptyDay = testDir.appendingPathComponent("2026-01-01.json")
        try "[]".write(to: emptyDay, atomically: true, encoding: .utf8)

        logger.scanForDates()
        let hasJan1 = logger.datesWithLogs.contains {
            WorkMonitorDates.storageDayString(for: $0) == "2026-01-01"
        }
        XCTAssertFalse(hasJan1, "Empty day files should not appear in datesWithLogs")
    }

    func testScanForDatesFindsMultipleDays() throws {
        let entry = LogEntry(activity: "Old task")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([entry])
        let oldDay = testDir.appendingPathComponent("2026-03-10.json")
        try data.write(to: oldDay)

        logger.log(activity: "Today")
        logger.scanForDates()

        XCTAssertGreaterThanOrEqual(logger.datesWithLogs.count, 2)
    }

    // MARK: - Date selection

    func testSelectTodayIsViewingToday() {
        logger.selectToday()
        XCTAssertTrue(logger.isViewingToday)
    }

    func testSelectHistoricalDateNotViewingToday() {
        guard let oldDate = WorkMonitorDates.date(fromStorageDayString: "2026-01-01") else {
            XCTFail("Could not parse date")
            return
        }
        logger.selectDate(oldDate)
        XCTAssertFalse(logger.isViewingToday)
    }

    func testDisplayedEntriesSwitchesWithSelectedDate() throws {
        let oldEntry = LogEntry(activity: "Old work")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([oldEntry])
        let oldDay = testDir.appendingPathComponent("2026-03-10.json")
        try data.write(to: oldDay)

        logger.log(activity: "Today's work")
        XCTAssertEqual(logger.displayedEntries.first?.activity, "Today's work")

        guard let oldDate = WorkMonitorDates.date(fromStorageDayString: "2026-03-10") else {
            XCTFail("Could not parse date")
            return
        }
        logger.selectDate(oldDate)
        XCTAssertEqual(logger.displayedEntries.first?.activity, "Old work")

        logger.selectToday()
        XCTAssertEqual(logger.displayedEntries.first?.activity, "Today's work")
    }
}
