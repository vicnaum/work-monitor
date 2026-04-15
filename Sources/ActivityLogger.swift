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

    private var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".work-monitor/logs")
    }

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

    init() {
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
            .filter { !loadEntries(from: $0).isEmpty }
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
        let sortedEntries = todayEntries.sorted { $0.timestamp < $1.timestamp }
        if sortedEntries.isEmpty {
            if FileManager.default.fileExists(atPath: todayFileURL.path) {
                try? FileManager.default.removeItem(at: todayFileURL)
            }
            if FileManager.default.fileExists(atPath: todayMarkdownURL.path) {
                try? FileManager.default.removeItem(at: todayMarkdownURL)
            }
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sortedEntries) else { return }
        try? data.write(to: todayFileURL, options: .atomic)
        saveMarkdown(entries: sortedEntries)
    }

    private func saveMarkdown(entries: [LogEntry]) {
        var md = "# Work Log — \(WorkMonitorDates.fullDateString(for: Date()))\n\n"
        for entry in entries {
            md += "- **\(WorkMonitorDates.timeString(for: entry.timestamp))** — \(entry.activity)\n"
        }

        try? md.write(to: todayMarkdownURL, atomically: true, encoding: .utf8)
    }
}
