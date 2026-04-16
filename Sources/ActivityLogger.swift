import Foundation
import Combine

struct LogEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let activity: String

    init(activity: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.activity = activity
    }
}

enum LogDirectoryMoveError: LocalizedError {
    case destinationAlreadyContainsFile(String)

    var errorDescription: String? {
        switch self {
        case .destinationAlreadyContainsFile(let filename):
            return "The destination folder already contains \(filename)."
        }
    }

    var recoverySuggestion: String? {
        "Choose a different folder, or remove the conflicting file and try again."
    }
}

@MainActor
final class ActivityLogger: ObservableObject {
    @Published var todayEntries: [LogEntry] = []
    @Published var selectedDate = Date()
    @Published var historicalEntries: [LogEntry] = []
    @Published var datesWithLogs: [Date] = []
    @Published private(set) var logDirectory: URL
    @Published var isLoading = false
    @Published var lastError: StoreError?
    let appLaunchTime = Date()
    private let persistsLogDirectory: Bool
    private let userDefaults: UserDefaults
    private let store: ActivityLogStore

    var isViewingToday: Bool {
        WorkMonitorDates.uiCalendar.isDateInToday(selectedDate)
    }

    var displayedEntries: [LogEntry] {
        isViewingToday ? todayEntries : historicalEntries
    }

    var selectedDateFormatted: String {
        WorkMonitorDates.mediumDateString(for: selectedDate)
    }

    init(logDirectory: URL? = nil, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let resolvedLogDirectory: URL
        if let logDirectory {
            resolvedLogDirectory = logDirectory.standardizedFileURL
            self.persistsLogDirectory = false
        } else {
            resolvedLogDirectory = WorkMonitorPaths.resolvedLogDirectory(userDefaults: userDefaults)
            self.persistsLogDirectory = true
        }
        self.logDirectory = resolvedLogDirectory
        self.store = ActivityLogStore(logDirectory: resolvedLogDirectory)

        Task { @MainActor [weak self] in
            await self?.prepareInitialState()
        }
    }

    func log(activity: String) async {
        let entry = LogEntry(activity: activity)
        todayEntries.insert(entry, at: 0)
        await persistTodayEntries()
        datesWithLogs = await store.storedLogDates()
    }

    func loadToday() async {
        await withLoadingIndicator {
            todayEntries = await store.loadEntries(for: Date())
        }
    }

    func hasStoredLogs() async -> Bool {
        await store.hasStoredLogs()
    }

    func setLogDirectory(_ url: URL) async {
        let newDirectory = url.standardizedFileURL
        do {
            try await store.setLogDirectory(newDirectory)
        } catch {
            surfaceError(error)
        }
        logDirectory = newDirectory
        if persistsLogDirectory {
            WorkMonitorPaths.setStoredLogDirectory(newDirectory, userDefaults: userDefaults)
        }
        await reloadEntriesForCurrentDirectory()
    }

    func moveLogs(to url: URL) async throws {
        let destinationDirectory = try await store.moveLogs(to: url)
        logDirectory = destinationDirectory
        if persistsLogDirectory {
            WorkMonitorPaths.setStoredLogDirectory(destinationDirectory, userDefaults: userDefaults)
        }
        await reloadEntriesForCurrentDirectory()
    }

    func selectDate(_ date: Date) async {
        selectedDate = date
        if !isViewingToday {
            await withLoadingIndicator {
                historicalEntries = await store.loadEntries(for: date)
            }
        }
    }

    func selectToday() {
        selectedDate = Date()
    }

    func deleteEntry(_ entry: LogEntry) async {
        if isViewingToday {
            todayEntries.removeAll { $0.id == entry.id }
            await persistTodayEntries()
            datesWithLogs = await store.storedLogDates()
        }
    }

    func dismissError() {
        lastError = nil
    }

    func slackFormatted(date: Date, entries: [LogEntry], showTimestamps: Bool) -> String {
        let header = "*Daily Update — \(WorkMonitorDates.mediumDateString(for: date))*"
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        if sorted.isEmpty { return header + "\nNo entries yet." }

        let lines: [String]
        if showTimestamps {
            lines = sorted.map { "• \(WorkMonitorDates.timeString(for: $0.timestamp)) — \($0.activity)" }
        } else {
            lines = sorted.map { "• \($0.activity)" }
        }
        return header + "\n" + lines.joined(separator: "\n")
    }

    func scanForDates() async {
        datesWithLogs = await store.storedLogDates()
    }

    // MARK: - Private

    private func prepareInitialState() async {
        do {
            try await store.ensureLogDirectoryExists()
        } catch {
            surfaceError(error)
        }
        await reloadEntriesForCurrentDirectory()
    }

    private func reloadEntriesForCurrentDirectory() async {
        await withLoadingIndicator {
            todayEntries = await store.loadEntries(for: Date())
            if isViewingToday {
                historicalEntries = []
            } else {
                historicalEntries = await store.loadEntries(for: selectedDate)
            }
            datesWithLogs = await store.storedLogDates()
        }
    }

    private func persistTodayEntries() async {
        do {
            try await store.save(entries: todayEntries, for: Date())
        } catch {
            surfaceError(error)
        }
    }

    private func surfaceError(_ error: Error) {
        if let storeError = error as? StoreError {
            lastError = storeError
        } else {
            lastError = .saveFailed(error.localizedDescription)
        }
    }

    private func withLoadingIndicator(_ operation: () async -> Void) async {
        let showLoaderTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            isLoading = true
        }
        await operation()
        showLoaderTask.cancel()
        isLoading = false
    }
}
