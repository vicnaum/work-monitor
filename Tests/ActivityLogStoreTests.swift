import XCTest
@testable import WorkMonitorLib

final class ActivityLogStoreTests: XCTestCase {
    private var testDir: URL!
    private var store: ActivityLogStore!

    override func setUp() async throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkMonitorStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        store = ActivityLogStore(logDirectory: testDir)
        try await store.ensureLogDirectoryExists()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDir)
    }

    func testLoadEntriesQuarantinesCorruptJsonAndMarkdown() async throws {
        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let jsonFile = testDir.appendingPathComponent("\(dayString).json")
        let markdownFile = testDir.appendingPathComponent("\(dayString).md")

        try "{broken".write(to: jsonFile, atomically: true, encoding: .utf8)
        try "old markdown".write(to: markdownFile, atomically: true, encoding: .utf8)

        do {
            _ = try await store.loadEntries(for: Date())
            XCTFail("Expected corrupt JSON to throw")
        } catch let error as StoreError {
            guard case .decodeFailed(let filename, let preservedAs, _) = error else {
                return XCTFail("Unexpected store error: \(error)")
            }

            XCTAssertEqual(filename, "\(dayString).json")
            XCTAssertTrue(preservedAs.hasPrefix("\(dayString).corrupt-"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: jsonFile.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: markdownFile.path))

            let files = try FileManager.default.contentsOfDirectory(
                at: testDir,
                includingPropertiesForKeys: nil
            )
            XCTAssertTrue(files.contains { $0.lastPathComponent == preservedAs })
            XCTAssertTrue(files.contains {
                $0.lastPathComponent.hasPrefix("\(dayString).corrupt-") && $0.pathExtension == "md"
            })
        }
    }

    func testSaveAfterCorruptLoadWritesFreshFileAndKeepsPreservedCopy() async throws {
        let dayString = WorkMonitorDates.storageDayString(for: Date())
        let jsonFile = testDir.appendingPathComponent("\(dayString).json")
        let markdownFile = testDir.appendingPathComponent("\(dayString).md")

        try "{broken".write(to: jsonFile, atomically: true, encoding: .utf8)
        try "old markdown".write(to: markdownFile, atomically: true, encoding: .utf8)

        do {
            _ = try await store.loadEntries(for: Date())
            XCTFail("Expected corrupt JSON to throw")
        } catch {
            // Expected.
        }

        try await store.save(entries: [LogEntry(activity: "Recovered")], for: Date())

        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonFile.path))
        let files = try FileManager.default.contentsOfDirectory(
            at: testDir,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(files.contains {
            $0.lastPathComponent.hasPrefix("\(dayString).corrupt-") && $0.pathExtension == "json"
        })
    }
}
