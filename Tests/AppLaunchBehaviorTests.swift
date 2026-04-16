import AppKit
import XCTest
@testable import WorkMonitorLib

final class AppLaunchBehaviorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppLaunchBehaviorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testShouldShowInitialPanelOnFirstManualLaunch() {
        XCTAssertTrue(AppLaunchBehavior.shouldShowInitialPanel(
            launchedAtLogin: false,
            userDefaults: defaults
        ))
    }

    func testShouldNotShowInitialPanelWhenLaunchedAtLogin() {
        XCTAssertFalse(AppLaunchBehavior.shouldShowInitialPanel(
            launchedAtLogin: true,
            userDefaults: defaults
        ))
    }

    func testShouldNotShowInitialPanelAfterMarkingShown() {
        AppLaunchBehavior.markInitialPanelShown(userDefaults: defaults)

        XCTAssertFalse(AppLaunchBehavior.shouldShowInitialPanel(
            launchedAtLogin: false,
            userDefaults: defaults
        ))
    }

    func testWasLaunchedAtLoginRecognizesLoginAppleEvent() {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(
            NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem),
            forKeyword: AEKeyword(keyAEPropData)
        )

        XCTAssertTrue(AppLaunchBehavior.wasLaunchedAtLogin(event))
    }

    func testWasLaunchedAtLoginIgnoresRegularOpenEvent() {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )

        XCTAssertFalse(AppLaunchBehavior.wasLaunchedAtLogin(event))
    }
}
