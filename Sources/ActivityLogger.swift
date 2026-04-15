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
        Calendar.current.isDateInToday(selectedDate)
    }

    var displayedEntries: [LogEntry] {
        isViewingToday ? todayEntries : historicalEntries
    }

    var selectedDateFormatted: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: selectedDate)
    }

    private var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".work-monitor/logs")
    }

    private func dateString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private var todayDateString: String { dateString(for: Date()) }

    private var todayFileURL: URL {
        logDirectory.appendingPathComponent(todayDateString + ".json")
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
        }
        // Don't allow deleting historical entries
    }

    func slackFormatted(date: Date, entries: [LogEntry], showTimestamps: Bool) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .medium

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        let header = "*Daily Update — \(dateFmt.string(from: date))*"
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        if sorted.isEmpty { return header + "\nNo entries yet." }

        let lines: [String]
        if showTimestamps {
            lines = sorted.map { "• \(timeFmt.string(from: $0.timestamp)) — \($0.activity)" }
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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        datesWithLogs = files
            .filter { $0.pathExtension == "json" }
            .compactMap { f.date(from: $0.deletingPathExtension().lastPathComponent) }
            .sorted(by: >)
    }

    // MARK: - Private

    private func loadEntries(for date: Date) -> [LogEntry] {
        let fileURL = logDirectory.appendingPathComponent(dateString(for: date) + ".json")
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([LogEntry].self, from: data) else { return [] }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(
            todayEntries.sorted { $0.timestamp < $1.timestamp }
        ) else { return }
        try? data.write(to: todayFileURL, options: .atomic)
        saveMarkdown()
    }

    private func saveMarkdown() {
        let dateFmt = DateFormatter()
        dateFmt.dateStyle = .full

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        var md = "# Work Log — \(dateFmt.string(from: Date()))\n\n"
        let sorted = todayEntries.sorted { $0.timestamp < $1.timestamp }
        for entry in sorted {
            md += "- **\(timeFmt.string(from: entry.timestamp))** — \(entry.activity)\n"
        }

        let mdURL = logDirectory.appendingPathComponent(todayDateString + ".md")
        try? md.write(to: mdURL, atomically: true, encoding: .utf8)
    }
}
