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

    func testLogCreatesEntry() async {
        XCTAssertEqual(logger.todayEntries.count, 0)
        await logger.log(activity: "Test task")
        XCTAssertEqual(logger.todayEntries.count, 1)
        XCTAssertEqual(logger.todayEntries.first?.activity, "Test task")
    }

    func testLogMultipleEntries() async {
        await logger.log(activity: "First")
        await logger.log(activity: "Second")
        await logger.log(activity: "Third")
        XCTAssertEqual(logger.todayEntries.count, 3)
        // Most recent first
        XCTAssertEqual(logger.todayEntries.first?.activity, "Third")
    }

    func testLogPersistsToFile() async {
        await logger.log(activity: "Persistent task")

        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let jsonFile = testDir.appendingPathComponent("\(dayString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonFile.path))

        let mdFile = testDir.appendingPathComponent("\(dayString).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mdFile.path))
    }

    func testLoadTodayReadsPersistedEntries() async {
        await logger.log(activity: "Task A")
        await logger.log(activity: "Task B")

        let logger2 = ActivityLogger(logDirectory: testDir)
        await logger2.loadToday()
        XCTAssertEqual(logger2.todayEntries.count, 2)
    }

    func testLoadTodaySurfacesDecodeErrorAndPreservesCorruptFile() async throws {
        // Ensure the logger's init Task has completed before we corrupt the file
        await logger.loadToday()

        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let jsonFile = testDir.appendingPathComponent("\(dayString).json")
        try "{not valid json".write(to: jsonFile, atomically: true, encoding: .utf8)

        await logger.loadToday()

        guard case .decodeFailed(let filename, let preservedAs, _) = logger.lastError else {
            return XCTFail("Expected a decode error, got \(String(describing: logger.lastError))")
        }

        XCTAssertEqual(filename, "\(dayString).json")
        XCTAssertTrue(preservedAs.hasPrefix("\(dayString).corrupt-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonFile.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: testDir.appendingPathComponent(preservedAs).path
        ))
    }

    func testSetLogDirectoryReloadsEntriesFromNewFolder() async throws {
        await logger.log(activity: "Original folder")

        let otherDir = testDir.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([LogEntry(activity: "New folder")])
        let dayString = WorkMonitorDates.storageDayString(for: Date())
        try data.write(to: otherDir.appendingPathComponent("\(dayString).json"))

        await logger.setLogDirectory(otherDir)

        XCTAssertEqual(logger.logDirectory.standardizedFileURL.path, otherDir.standardizedFileURL.path)
        XCTAssertEqual(logger.todayEntries.count, 1)
        XCTAssertEqual(logger.todayEntries.first?.activity, "New folder")
    }

    func testHasStoredLogsIsFalseForEmptyDirectory() async {
        let hasStoredLogs = await logger.hasStoredLogs()
        XCTAssertFalse(hasStoredLogs)
    }

    func testHasStoredLogsIgnoresEmptyJsonFiles() async throws {
        let emptyDay = testDir.appendingPathComponent("2026-01-01.json")
        try "[]".write(to: emptyDay, atomically: true, encoding: .utf8)

        let hasStoredLogs = await logger.hasStoredLogs()
        XCTAssertFalse(hasStoredLogs)
    }

    func testMoveLogsMovesExistingFilesAndReloadsEntries() async throws {
        await logger.log(activity: "Move me")

        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let sourceJSON = testDir.appendingPathComponent("\(dayString).json")
        let sourceMarkdown = testDir.appendingPathComponent("\(dayString).md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceJSON.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceMarkdown.path))

        let otherDir = testDir.appendingPathComponent("Moved")
        try await logger.moveLogs(to: otherDir)

        XCTAssertEqual(logger.logDirectory.path, otherDir.standardizedFileURL.path)
        XCTAssertEqual(logger.todayEntries.first?.activity, "Move me")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceJSON.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceMarkdown.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: otherDir.standardizedFileURL.appendingPathComponent("\(dayString).json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: otherDir.standardizedFileURL.appendingPathComponent("\(dayString).md").path
        ))
    }

    func testMoveLogsThrowsWhenDestinationAlreadyContainsSameFile() async throws {
        await logger.log(activity: "Conflict")

        let otherDir = testDir.appendingPathComponent("Conflict")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)

        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let conflictingFile = otherDir.appendingPathComponent("\(dayString).json")
        try "[]".write(to: conflictingFile, atomically: true, encoding: .utf8)

        do {
            try await logger.moveLogs(to: otherDir)
            XCTFail("Expected move to fail")
        } catch {
            guard case LogDirectoryMoveError.destinationAlreadyContainsFile(let filename) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(filename, "\(dayString).json")
        }
        XCTAssertEqual(logger.logDirectory, testDir.standardizedFileURL)
    }

    // MARK: - Deletion

    func testDeleteEntry() async {
        await logger.log(activity: "Keep this")
        await logger.log(activity: "Delete this")
        let toDelete = logger.todayEntries.first! // "Delete this" (most recent)
        await logger.deleteEntry(toDelete)
        XCTAssertEqual(logger.todayEntries.count, 1)
        XCTAssertEqual(logger.todayEntries.first?.activity, "Keep this")
    }

    func testDeleteLastEntryRemovesFiles() async {
        await logger.log(activity: "Only entry")
        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let jsonFile = testDir.appendingPathComponent("\(dayString).json")
        let mdFile = testDir.appendingPathComponent("\(dayString).md")

        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonFile.path))

        await logger.deleteEntry(logger.todayEntries.first!)
        XCTAssertEqual(logger.todayEntries.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonFile.path),
                       "JSON file should be removed when all entries deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: mdFile.path),
                       "Markdown file should be removed when all entries deleted")
    }

    func testDeleteLastEntryRemovesFromDatesWithLogs() async {
        await logger.log(activity: "Temp entry")
        XCTAssertFalse(logger.datesWithLogs.isEmpty)

        await logger.deleteEntry(logger.todayEntries.first!)
        XCTAssertTrue(logger.datesWithLogs.isEmpty,
                      "datesWithLogs should not include days with no entries")
    }

    // MARK: - Slack formatting

    func testSlackFormattedWithTimestamps() async {
        await logger.log(activity: "Did something")
        let result = logger.slackFormatted(
            date: Date(), entries: logger.todayEntries, showTimestamps: true
        )
        XCTAssertTrue(result.contains("*Daily Update"))
        XCTAssertTrue(result.contains("Did something"))
        XCTAssertTrue(result.contains(":"), "Should contain a time with colon")
    }

    func testSlackFormattedWithoutTimestamps() async {
        await logger.log(activity: "Did something")
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

    func testScanForDatesFindsLoggedDays() async {
        await logger.log(activity: "Today's task")
        await logger.scanForDates()
        XCTAssertEqual(logger.datesWithLogs.count, 1)
    }

    func testScanForDatesIgnoresEmptyFiles() async throws {
        let emptyDay = testDir.appendingPathComponent("2026-01-01.json")
        try "[]".write(to: emptyDay, atomically: true, encoding: .utf8)

        await logger.scanForDates()
        let hasJan1 = logger.datesWithLogs.contains {
            WorkMonitorDates.storageDayString(for: $0) == "2026-01-01"
        }
        XCTAssertFalse(hasJan1, "Empty day files should not appear in datesWithLogs")
    }

    func testScanForDatesFindsMultipleDays() async throws {
        let entry = LogEntry(activity: "Old task")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([entry])
        let oldDay = testDir.appendingPathComponent("2026-03-10.json")
        try data.write(to: oldDay)

        await logger.log(activity: "Today")
        await logger.scanForDates()

        XCTAssertGreaterThanOrEqual(logger.datesWithLogs.count, 2)
    }

    // MARK: - Date selection

    func testSelectTodayIsViewingToday() async {
        await logger.selectToday()
        XCTAssertTrue(logger.isViewingToday)
    }

    func testSelectHistoricalDateNotViewingToday() async {
        guard let oldDate = WorkMonitorDates.date(fromStorageDayString: "2026-01-01") else {
            XCTFail("Could not parse date")
            return
        }
        await logger.selectDate(oldDate)
        XCTAssertFalse(logger.isViewingToday)
    }

    func testDisplayedEntriesSwitchesWithSelectedDate() async throws {
        let oldEntry = LogEntry(activity: "Old work")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([oldEntry])
        let oldDay = testDir.appendingPathComponent("2026-03-10.json")
        try data.write(to: oldDay)

        await logger.log(activity: "Today's work")
        XCTAssertEqual(logger.displayedEntries.first?.activity, "Today's work")

        guard let oldDate = WorkMonitorDates.date(fromStorageDayString: "2026-03-10") else {
            XCTFail("Could not parse date")
            return
        }
        await logger.selectDate(oldDate)
        XCTAssertEqual(logger.displayedEntries.first?.activity, "Old work")

        await logger.selectToday()
        XCTAssertEqual(logger.displayedEntries.first?.activity, "Today's work")
    }
}
