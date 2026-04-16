import SwiftUI

struct MenuBarView: View {
    @ObservedObject var logger: ActivityLogger
    @ObservedObject var settings: AppSettings
    let dismissPanel: () -> Void
    @State private var activityText = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var now = Date()
    @State private var clockTask: Task<Void, Never>?
    @State private var isAutoOpened = false
    @State private var autoDismissing = false
    @State private var autoDismissProgress: CGFloat = 0
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var motivationalText: String = Self.randomMotivation()
    @State private var motivationalColor: Color = Self.randomBrightColor()
    @State private var showingCalendar = false

    private static let brightColors: [Color] = [
        .orange, .pink, .purple, .mint, .teal, .cyan, .indigo,
        Color(red: 1, green: 0.4, blue: 0.4),    // coral
        Color(red: 0.2, green: 0.8, blue: 0.4),   // lime
        Color(red: 1, green: 0.6, blue: 0),        // amber
        Color(red: 0.6, green: 0.4, blue: 1),      // lavender
        Color(red: 1, green: 0.3, blue: 0.6),      // hot pink
    ]

    private static func randomBrightColor() -> Color {
        brightColors.randomElement() ?? .orange
    }

    private static let motivations = [
        "Time to stretch!",
        "Well done, now take a break!",
        "Stand up, grab some water!",
        "Great work! Roll your shoulders.",
        "Look away from the screen for 20 seconds.",
        "Take a deep breath.",
        "Nice progress! Rest your eyes.",
        "You're doing great, keep it up!",
        "Move around a bit, your body will thank you.",
        "Quick break? Your brain needs it.",
    ]

    private static func randomMotivation() -> String {
        motivations.randomElement() ?? "Time to stretch!"
    }

    private var timeSinceLastEntry: String {
        let reference: Date
        if let lastEntry = logger.todayEntries.first?.timestamp {
            reference = lastEntry
        } else {
            reference = logger.appLaunchTime
        }
        let minutes = Int(now.timeIntervalSince(reference) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)min" }
        let hours = minutes / 60
        let remainingMin = minutes % 60
        if remainingMin == 0 { return "\(hours)h" }
        return "\(hours)h \(remainingMin)min"
    }

    private var displayedEntries: [LogEntry] {
        logger.displayedEntries
    }

    private var logDirectoryDisplayPath: String {
        WorkMonitorPaths.displayPath(for: logger.logDirectory)
    }

    private var logDirectoryTooltip: String {
        "Change log folder\nCurrent: \(logger.logDirectory.path)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Motivational text (only when viewing today)
            if logger.isViewingToday {
                Text(motivationalText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(motivationalColor)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Clock + question
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(now, format: .dateTime.hour().minute())
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)

                    Text("What have you been working on for the last \(timeSinceLastEntry)?")
                        .font(.system(size: 22))
                        .foregroundStyle(.primary)
                }

                // Input
                TextEditor(text: $activityText)
                    .font(.body)
                    .frame(height: 70)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                    .focused($isTextFieldFocused)
                    .onKeyPress(keys: [.return, .init("\r")], phases: .down) { _ in
                        logActivity()
                        return .handled
                    }

                HStack {
                    Button("Log It") { logActivity() }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .disabled(activityText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
            } else {
                // Viewing historical date
                HStack {
                    Button {
                        logger.selectToday()
                    } label: {
                        Label("Back to Today", systemImage: "arrow.left")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }

            Divider()

            // Date header
            HStack {
                if logger.isViewingToday {
                    Text("Today")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                } else {
                    Text(logger.selectedDateFormatted)
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                }

                Button {
                    showingCalendar.toggle()
                } label: {
                    Label(
                        showingCalendar ? "Hide Calendar" : "Show Calendar",
                        systemImage: showingCalendar ? "calendar.circle.fill" : "calendar"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("\(displayedEntries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Calendar or entries (same space)
            if showingCalendar {
                CalendarSection(logger: logger, showingCalendar: $showingCalendar)
            } else if displayedEntries.isEmpty {
                Spacer()
                Text(logger.isViewingToday
                     ? "No entries today yet. Start logging!"
                     : "No entries for this day.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(displayedEntries) { entry in
                            EntryRow(
                                entry: entry,
                                canDelete: logger.isViewingToday,
                                showTimestamp: settings.showTimestamps
                            ) {
                                logger.deleteEntry(entry)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            // Actions
            HStack(spacing: 8) {
                IconToggleButton(
                    systemName: "clock",
                    enabled: settings.showTimestamps,
                    tooltip: settings.showTimestamps ? "Hide times" : "Show times"
                ) {
                    settings.showTimestamps.toggle()
                }

                Button {
                    let text = logger.slackFormatted(
                        date: logger.selectedDate,
                        entries: displayedEntries,
                        showTimestamps: settings.showTimestamps
                    )
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("Copy for Slack", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .disabled(displayedEntries.isEmpty)

                Button {
                    NSWorkspace.shared.open(logger.logDirectory)
                } label: {
                    Label("Open Logs", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                LogDirectoryLinkButton(
                    path: logDirectoryDisplayPath,
                    tooltip: logDirectoryTooltip
                ) {
                    chooseLogDirectory()
                }

                Spacer()

                HStack(spacing: 10) {
                    // Sound toggle
                    IconToggleButton(
                        systemName: "speaker.wave.2",
                        enabled: settings.soundEnabled,
                        tooltip: settings.soundEnabled ? "Mute sound" : "Enable sound"
                    ) {
                        settings.soundEnabled.toggle()
                    }

                    // Reminders toggle
                    IconToggleButton(
                        systemName: "bell",
                        enabled: settings.remindersEnabled,
                        tooltip: settings.remindersEnabled ? "Disable reminders" : "Enable reminders"
                    ) {
                        settings.remindersEnabled.toggle()
                    }

                    Picker("", selection: $settings.intervalMinutes) {
                        ForEach(AppSettings.intervalOptions, id: \.self) { min in
                            Text(min < 60 ? "\(min)min" : "1hr").tag(min)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                    .disabled(!settings.remindersEnabled)
                    .opacity(settings.remindersEnabled ? 1 : 0.4)
                }

                Button {
                    cancelAutoDismiss()
                    dismissPanel()
                } label: {
                    Text("Dismiss")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if autoDismissing {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture { cancelAutoDismiss() }

                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: autoDismissProgress)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "checkmark")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 80, height: 80)

                    Text("Logged!")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                .transition(.opacity)
            }
        }
        .onChange(of: activityText) {
            if autoDismissing && !activityText.isEmpty {
                cancelAutoDismiss()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelWillShow)) { _ in
            motivationalText = Self.randomMotivation()
            motivationalColor = Self.randomBrightColor()
            logger.selectToday()
            startClock()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelShowedByReminder)) { _ in
            isAutoOpened = true
            cancelAutoDismiss()
            isTextFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelShowedManually)) { _ in
            isAutoOpened = false
            cancelAutoDismiss()
            isTextFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            isAutoOpened = false
            cancelAutoDismiss()
            stopClock()
        }
        .onDisappear {
            cancelAutoDismiss()
            stopClock()
        }
    }

    @MainActor
    private func startClock() {
        now = Date()
        guard clockTask == nil else { return }

        clockTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                now = Date()
            }
        }
    }

    @MainActor
    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func logActivity() {
        let trimmed = activityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logger.log(activity: trimmed)
        activityText = ""
        isTextFieldFocused = true

        if isAutoOpened {
            startAutoDismiss()
        }
    }

    private func startAutoDismiss() {
        autoDismissing = true
        autoDismissProgress = 0
        withAnimation(.linear(duration: 1.0)) {
            autoDismissProgress = 1.0
        }
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            autoDismissing = false
            autoDismissProgress = 0
            isAutoOpened = false
            dismissPanel()
        }
    }

    private func cancelAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        if autoDismissing {
            withAnimation(.easeOut(duration: 0.2)) {
                autoDismissing = false
                autoDismissProgress = 0
            }
        }
    }

    private func chooseLogDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Log Folder"
        panel.message = "Choose where Work Monitor stores your daily log files."
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = logger.logDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        logger.setLogDirectory(url)
    }
}

// MARK: - Calendar Section

struct CalendarSection: View {
    @ObservedObject var logger: ActivityLogger
    @Binding var showingCalendar: Bool

    private let calendar = WorkMonitorDates.uiCalendar
    @State private var displayedMonth = Date()

    private var datesWithLogsSet: Set<String> {
        Set(logger.datesWithLogs.map { WorkMonitorDates.storageDayString(for: $0) })
    }

    private var weekdays: [String] {
        WorkMonitorDates.orderedWeekdaySymbols()
    }

    private var monthTitle: String {
        WorkMonitorDates.monthTitle(for: displayedMonth)
    }

    private var daysInMonth: [Date?] {
        WorkMonitorDates.daysInMonth(for: displayedMonth)
    }

    private var displayedMonthStart: Date {
        WorkMonitorDates.startOfMonth(for: displayedMonth)
    }

    private var canNavigateForward: Bool {
        WorkMonitorDates.canNavigateForward(from: displayedMonthStart)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Month nav
            HStack {
                Button {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonthStart) ?? displayedMonthStart
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()
                Text(monthTitle)
                    .font(.headline)
                Spacer()

                Button {
                    guard canNavigateForward else { return }
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonthStart) ?? displayedMonthStart
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(!canNavigateForward)
            }

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            date: date,
                            hasLog: datesWithLogsSet.contains(WorkMonitorDates.storageDayString(for: date)),
                            isToday: calendar.isDateInToday(date),
                            isSelected: calendar.isDate(date, inSameDayAs: logger.selectedDate),
                            isFuture: WorkMonitorDates.isFutureDay(date)
                        ) {
                            logger.selectDate(date)
                            showingCalendar = false
                        }
                    } else {
                        Color.clear
                            .frame(height: 40)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            displayedMonth = WorkMonitorDates.startOfMonth(for: logger.selectedDate)
            logger.scanForDates()
        }
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let hasLog: Bool
    let isToday: Bool
    let isSelected: Bool
    let isFuture: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("\(WorkMonitorDates.uiCalendar.component(.day, from: date))")
                .font(.system(size: 14, weight: isToday || hasLog ? .bold : .regular))
                .foregroundStyle(
                    isFuture ? Color.secondary.opacity(0.3) :
                    isSelected ? Color.white :
                    isToday ? Color.red :
                    Color.primary
                )
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isSelected ? Color.accentColor :
                            hasLog ? Color.green.opacity(0.15) :
                            Color.clear
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isToday ? Color.red :
                            isHovered && !isFuture ? Color.red.opacity(0.3) :
                            Color.clear,
                            lineWidth: isToday ? 2 : 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(isFuture)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Entry Row

struct EntryRow: View {
    let entry: LogEntry
    var canDelete: Bool = true
    var showTimestamp: Bool = true
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showTimestamp {
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)
            }

            Text(entry.activity)
                .font(.body)

            Spacer()

            if isHovered && canDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Log Directory Link

struct LogDirectoryLinkButton: View {
    let path: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    private var linkColor: Color {
        let baseColor = Color(nsColor: .linkColor)
        return isHovered ? baseColor.opacity(0.75) : baseColor
    }

    var body: some View {
        Button(action: action) {
            Text(path)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(linkColor)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    DottedUnderline(color: linkColor)
                        .offset(y: 1)
                }
                .frame(maxWidth: 230, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}

private struct DottedUnderline: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
        }
        .frame(height: 1)
        .allowsHitTesting(false)
    }
}

// MARK: - Icon Toggle

struct IconToggleButton: View {
    let systemName: String
    let enabled: Bool
    let tooltip: String
    var tooltipAlignment: Alignment = .top
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ToggleIcon(systemName: systemName, enabled: enabled)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .background {
            if isHovered {
                FloatingTooltipAnchor(text: tooltip)
                    .frame(width: 1, height: 1)
            }
        }
    }
}

// MARK: - Floating Tooltip (separate NSWindow, never clips)

struct FloatingTooltipAnchor: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let text = self.text
        DispatchQueue.main.async {
            guard nsView.window != nil else { return }
            FloatingTooltipManager.shared.show(text: text, relativeTo: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        FloatingTooltipManager.shared.hide()
    }
}

@MainActor
final class FloatingTooltipManager {
    static let shared = FloatingTooltipManager()
    private var window: NSWindow?

    func show(text: String, relativeTo view: NSView) {
        hide()
        guard let parentWindow = view.window else { return }

        let tooltipContent = VStack(spacing: 0) {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .offset(y: -3)
        }

        let hostingView = NSHostingView(rootView: tooltipContent)
        let size = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: size)

        let tooltipWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        tooltipWindow.contentView = hostingView
        tooltipWindow.backgroundColor = .clear
        tooltipWindow.isOpaque = false
        tooltipWindow.hasShadow = true
        tooltipWindow.level = .floating + 1
        tooltipWindow.ignoresMouseEvents = true

        let viewFrame = view.convert(view.bounds, to: nil)
        let screenFrame = parentWindow.convertToScreen(viewFrame)
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.maxY + 4
        tooltipWindow.setFrameOrigin(NSPoint(x: x, y: y))

        tooltipWindow.alphaValue = 0
        parentWindow.addChildWindow(tooltipWindow, ordered: .above)
        self.window = tooltipWindow

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            tooltipWindow.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let w = window else { return }
        w.parent?.removeChildWindow(w)
        w.orderOut(nil)
        window = nil
    }
}

struct ToggleIcon: View {
    let systemName: String
    let enabled: Bool

    var body: some View {
        ZStack {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .opacity(enabled ? 1 : 0.4)

            if !enabled {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 18))
                    path.addLine(to: CGPoint(x: 18, y: 0))
                }
                .stroke(Color.red, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 18, height: 18)
            }
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let panelWillShow = Notification.Name("WorkMonitor.panelWillShow")
    static let panelShowedByReminder = Notification.Name("WorkMonitor.panelShowedByReminder")
    static let panelShowedManually = Notification.Name("WorkMonitor.panelShowedManually")
    static let panelDidHide = Notification.Name("WorkMonitor.panelDidHide")
}
