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

@MainActor
final class ActivityLogger: ObservableObject {
    @Published var todayEntries: [LogEntry] = []
    @Published var selectedDate = Date()
    @Published var historicalEntries: [LogEntry] = []
    @Published var datesWithLogs: [Date] = []
    let appLaunchTime = Date()

    var isViewingToday: Bool {
        WorkMonitorDates.uiCalendar.isDateInToday(selectedDate)
    }

    var displayedEntries: [LogEntry] {
        isViewingToday ? todayEntries : historicalEntries
    }

    var selectedDateFormatted: String {
        WorkMonitorDates.mediumDateString(for: selectedDate)
    }

    let logDirectory: URL

    private func entriesFileURL(for date: Date) -> URL {
        logDirectory.appendingPathComponent(WorkMonitorDates.storageDayString(for: date) + ".json")
    }

    private func markdownFileURL(for date: Date) -> URL {
        logDirectory.appendingPathComponent(WorkMonitorDates.storageDayString(for: date) + ".md")
    }

    private var todayFileURL: URL {
        entriesFileURL(for: Date())
    }

    private var todayMarkdownURL: URL {
        markdownFileURL(for: Date())
    }

    init(logDirectory: URL? = nil) {
        self.logDirectory = logDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".work-monitor/logs")
        ensureDirectoryExists()
        loadToday()
        scanForDates()
    }

    private func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: logDirectory, withIntermediateDirectories: true)
    }

    func log(activity: String) {
        let entry = LogEntry(activity: activity)
        todayEntries.insert(entry, at: 0)
        save()
        scanForDates()
    }

    func loadToday() {
        todayEntries = loadEntries(for: Date())
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        if !isViewingToday {
            historicalEntries = loadEntries(for: date)
        }
    }

    func selectToday() {
        selectedDate = Date()
    }

    func deleteEntry(_ entry: LogEntry) {
        if isViewingToday {
            todayEntries.removeAll { $0.id == entry.id }
            save()
            scanForDates()
        }
        // Don't allow deleting historical entries
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

    func scanForDates() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory, includingPropertiesForKeys: nil
        ) else {
            datesWithLogs = []
            return
        }
        datesWithLogs = files
            .filter { $0.pathExtension == "json" }
            .filter { (try? Data(contentsOf: $0))?.count ?? 0 > 4 } // skip empty "[]" files
            .compactMap { WorkMonitorDates.date(fromStorageDayString: $0.deletingPathExtension().lastPathComponent) }
            .sorted(by: >)
    }

    // MARK: - Private

    private func loadEntries(for date: Date) -> [LogEntry] {
        let fileURL = entriesFileURL(for: date)
        return loadEntries(from: fileURL)
    }

    private func loadEntries(from fileURL: URL) -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([LogEntry].self, from: data) else { return [] }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    private func save() {
        // Capture now once to avoid midnight boundary issues between file writes
        let now = Date()
        let jsonURL = entriesFileURL(for: now)
        let mdURL = markdownFileURL(for: now)

        let sortedEntries = todayEntries.sorted { $0.timestamp < $1.timestamp }
        if sortedEntries.isEmpty {
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                try? FileManager.default.removeItem(at: jsonURL)
            }
            if FileManager.default.fileExists(atPath: mdURL.path) {
                try? FileManager.default.removeItem(at: mdURL)
            }
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sortedEntries) else { return }
        try? data.write(to: jsonURL, options: .atomic)
        saveMarkdown(entries: sortedEntries, to: mdURL, date: now)
    }

    private func saveMarkdown(entries: [LogEntry], to url: URL, date: Date) {
        var md = "# Work Log — \(WorkMonitorDates.fullDateString(for: date))\n\n"
        for entry in entries {
            md += "- **\(WorkMonitorDates.timeString(for: entry.timestamp))** — \(entry.activity)\n"
        }

        try? md.write(to: url, atomically: true, encoding: .utf8)
    }
}
