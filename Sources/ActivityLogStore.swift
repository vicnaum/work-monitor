import Foundation

enum StoreError: LocalizedError, Sendable {
    case saveFailed(String)
    case directoryCreateFailed(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let detail): return "Failed to save log: \(detail)"
        case .directoryCreateFailed(let detail): return "Failed to create log directory: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .saveFailed: return "Check disk space and folder permissions for the log directory."
        case .directoryCreateFailed: return "Check that the parent folder exists and is writable."
        }
    }
}

actor ActivityLogStore {
    private var logDirectory: URL

    init(logDirectory: URL) {
        self.logDirectory = logDirectory.standardizedFileURL
    }

    func ensureLogDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(
                at: logDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw StoreError.directoryCreateFailed(error.localizedDescription)
        }
    }

    func setLogDirectory(_ url: URL) throws {
        logDirectory = url.standardizedFileURL
        try ensureLogDirectoryExists()
    }

    func hasStoredLogs() -> Bool {
        !storedLogDates().isEmpty
    }

    func moveLogs(to url: URL) throws -> URL {
        let destinationDirectory = url.standardizedFileURL
        guard destinationDirectory != logDirectory else { return destinationDirectory }

        let filesToMove = logFileURLs(in: logDirectory)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        for fileURL in filesToMove {
            let destinationFileURL = destinationDirectory.appendingPathComponent(fileURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationFileURL.path) {
                throw LogDirectoryMoveError.destinationAlreadyContainsFile(fileURL.lastPathComponent)
            }
        }

        for fileURL in filesToMove {
            let destinationFileURL = destinationDirectory.appendingPathComponent(fileURL.lastPathComponent)
            try FileManager.default.moveItem(at: fileURL, to: destinationFileURL)
        }

        logDirectory = destinationDirectory
        try ensureLogDirectoryExists()
        return destinationDirectory
    }

    func loadEntries(for date: Date) -> [LogEntry] {
        let fileURL = entriesFileURL(for: date)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([LogEntry].self, from: data) else { return [] }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }

    func save(entries: [LogEntry], for date: Date) throws {
        try ensureLogDirectoryExists()

        let jsonURL = entriesFileURL(for: date)
        let markdownURL = markdownFileURL(for: date)
        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }

        if sortedEntries.isEmpty {
            try? FileManager.default.removeItem(at: jsonURL)
            try? FileManager.default.removeItem(at: markdownURL)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(sortedEntries)
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            throw StoreError.saveFailed(error.localizedDescription)
        }
        saveMarkdown(entries: sortedEntries, to: markdownURL, date: date)
    }

    func storedLogDates() -> [Date] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .filter { (try? Data(contentsOf: $0))?.count ?? 0 > 4 } // skip empty "[]" files
            .compactMap { WorkMonitorDates.date(fromStorageDayString: $0.deletingPathExtension().lastPathComponent) }
            .sorted(by: >)
    }

    private func entriesFileURL(for date: Date) -> URL {
        logDirectory.appendingPathComponent(WorkMonitorDates.storageDayString(for: date) + ".json")
    }

    private func markdownFileURL(for date: Date) -> URL {
        logDirectory.appendingPathComponent(WorkMonitorDates.storageDayString(for: date) + ".md")
    }

    private func logFileURLs(in directory: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "json" || ext == "md"
        }
    }

    private func saveMarkdown(entries: [LogEntry], to url: URL, date: Date) {
        var markdown = "# Work Log — \(WorkMonitorDates.fullDateString(for: date))\n\n"
        for entry in entries {
            markdown += "- **\(WorkMonitorDates.timeString(for: entry.timestamp))** — \(entry.activity)\n"
        }

        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}
