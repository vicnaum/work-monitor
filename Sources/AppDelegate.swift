import AppKit
import SwiftUI
import Combine
import ServiceManagement

// Floating panel that works over full-screen apps
final class FloatingPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        if let onDismiss {
            onDismiss()
        } else {
            orderOut(nil)
        }
    }

    // Hide instead of destroy — we reuse the panel across show/hide cycles.
    override func close() {
        if let onDismiss {
            onDismiss()
        } else {
            super.close()
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var intervalMinutes: Int {
        didSet { UserDefaults.standard.set(intervalMinutes, forKey: "reminderInterval") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var remindersEnabled: Bool {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled") }
    }
    @Published var showTimestamps: Bool {
        didSet { UserDefaults.standard.set(showTimestamps, forKey: "showTimestamps") }
    }

    static let intervalOptions = [1, 2, 5, 10, 15, 20, 30, 60]

    init() {
        let savedInterval = UserDefaults.standard.integer(forKey: "reminderInterval")
        self.intervalMinutes = savedInterval > 0 ? savedInterval : 5
        let savedSound = UserDefaults.standard.object(forKey: "soundEnabled")
        self.soundEnabled = (savedSound as? Bool) ?? true
        let savedReminders = UserDefaults.standard.object(forKey: "remindersEnabled")
        self.remindersEnabled = (savedReminders as? Bool) ?? true
        let savedTimestamps = UserDefaults.standard.object(forKey: "showTimestamps")
        self.showTimestamps = (savedTimestamps as? Bool) ?? true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let logger = ActivityLogger()
    let settings = AppSettings()
    private var reminderTimer: Timer?
    private var reminderFocusTask: Task<Void, Never>?
    private var settingsCancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        startReminderTimer()

        // Restart timer when settings change
        settings.$intervalMinutes.sink { [weak self] _ in
            Task { @MainActor in self?.startReminderTimer() }
        }.store(in: &settingsCancellables)
        settings.$remindersEnabled.sink { [weak self] _ in
            Task { @MainActor in self?.startReminderTimer() }
        }.store(in: &settingsCancellables)
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = NSImage(
            systemSymbolName: "clock.fill",
            accessibilityDescription: "Work Monitor"
        )?.withSymbolConfiguration(config)

        button.action = #selector(handleClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPanel() {
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 750),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Work Monitor"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = false
        panel.titleVisibility = .visible
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.onDismiss = { [weak self] in
            self?.hidePanel()
        }
        let hostingController = NSHostingController(
            rootView: MenuBarView(
                logger: logger,
                settings: settings,
                dismissPanel: { [weak self] in self?.hidePanel() }
            )
        )
        hostingController.sizingOptions = []
        panel.contentViewController = hostingController
        panel.setContentSize(NSSize(width: 760, height: 750))
        panel.minSize = NSSize(width: 500, height: 400)
        panel.center()
    }

    private func startReminderTimer() {
        reminderTimer?.invalidate()
        guard settings.remindersEnabled else { return }

        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.minute, from: now)
        let second = calendar.component(.second, from: now)
        let intervalMin = settings.intervalMinutes

        // Next minute that's a multiple of the interval
        let nextMinute = ((minute / intervalMin) + 1) * intervalMin
        var secondsUntilNext = TimeInterval((nextMinute - minute) * 60 - second)
        if secondsUntilNext < 1 { secondsUntilNext += TimeInterval(intervalMin * 60) }

        // One-shot timer to align, then schedule the next one
        reminderTimer = Timer.scheduledTimer(
            withTimeInterval: secondsUntilNext, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showReminder()
                self?.startReminderTimer()
            }
        }
    }

    // MARK: - Menu bar actions

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let launchItem = NSMenuItem(
            title: launchAtLogin ? "Disable Launch at Login" : "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        if launchAtLogin {
            launchItem.state = .on
        }
        menu.addItem(launchItem)

        let soundItem = NSMenuItem(
            title: settings.soundEnabled ? "Disable Sound" : "Enable Sound",
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.target = self
        menu.addItem(soundItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Work Monitor",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Work Monitor: launch at login error — \(error)")
        }
    }

    @objc private func toggleSound() {
        settings.soundEnabled.toggle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Panel

    private func showReminder() {
        if settings.soundEnabled {
            NSSound(named: "Glass")?.play()
        }
        showPanel(isReminder: true)
    }

    private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel(isReminder: false)
        }
    }

    private func showPanel(isReminder: Bool) {
        reminderFocusTask?.cancel()
        reminderFocusTask = nil
        logger.loadToday()
        panel.center()
        NotificationCenter.default.post(name: .panelWillShow, object: nil)

        if isReminder {
            panel.orderFrontRegardless()
            reminderFocusTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(0.75))
                guard !Task.isCancelled, self.panel.isVisible else { return }
                self.panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .panelShowedByReminder, object: nil)
                self.reminderFocusTask = nil
            }
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .panelShowedManually, object: nil)
        }
    }

    private func hidePanel() {
        reminderFocusTask?.cancel()
        reminderFocusTask = nil
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        NotificationCenter.default.post(name: .panelDidHide, object: nil)
    }
}

