import AppKit

enum AppLaunchBehavior {
    static let hasShownInitialPanelKey = "hasShownInitialPanel"

    static func shouldShowInitialPanel(
        launchedAtLogin: Bool,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        !launchedAtLogin && !userDefaults.bool(forKey: hasShownInitialPanelKey)
    }

    static func markInitialPanelShown(userDefaults: UserDefaults = .standard) {
        userDefaults.set(true, forKey: hasShownInitialPanelKey)
    }

    static func wasLaunchedAtLogin(
        _ event: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
    ) -> Bool {
        guard let event else { return false }
        guard event.eventID == AEEventID(kAEOpenApplication) else { return false }

        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == keyAELaunchedAsLogInItem
    }
}
