import XCTest
@testable import WorkMonitorLib

final class WorkMonitorPathsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WorkMonitorPathsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultLogDirectoryUsesDocumentsFolder() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Work Monitor", isDirectory: true)

        XCTAssertEqual(WorkMonitorPaths.defaultLogDirectory(), expected)
    }

    func testResolvedLogDirectoryUsesStoredOverride() {
        let customURL = URL(fileURLWithPath: "/tmp/work-monitor-custom", isDirectory: true)
        WorkMonitorPaths.setStoredLogDirectory(customURL, userDefaults: defaults)

        XCTAssertEqual(
            WorkMonitorPaths.resolvedLogDirectory(userDefaults: defaults),
            customURL.standardizedFileURL
        )
    }

    func testSetStoredLogDirectoryNilClearsOverride() {
        let customURL = URL(fileURLWithPath: "/tmp/work-monitor-custom", isDirectory: true)
        WorkMonitorPaths.setStoredLogDirectory(customURL, userDefaults: defaults)
        WorkMonitorPaths.setStoredLogDirectory(nil, userDefaults: defaults)

        XCTAssertNil(WorkMonitorPaths.storedLogDirectory(userDefaults: defaults))
    }

    func testDisplayPathAbbreviatesHomeDirectory() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Work Monitor", isDirectory: true)

        XCTAssertEqual(WorkMonitorPaths.displayPath(for: url), "~/Documents/Work Monitor")
    }
}
