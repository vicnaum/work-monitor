import Foundation

actor ActivityLogStore {
    private var logDirectory: URL

    init(logDirectory: URL) {
        self.logDirectory = logDirectory.standardizedFileURL
    }

    func ensureLogDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
    }

    func setLogDirectory(_ url: URL) {
        logDirectory = url.standardizedFileURL
        ensureLogDirectoryExists()
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
        ensureLogDirectoryExists()
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

    func save(entries: [LogEntry], for date: Date) {
        ensureLogDirectoryExists()

        let jsonURL = entriesFileURL(for: date)
        let markdownURL = markdownFileURL(for: date)
        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }

        if sortedEntries.isEmpty {
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                try? FileManager.default.removeItem(at: jsonURL)
            }
            if FileManager.default.fileExists(atPath: markdownURL.path) {
                try? FileManager.default.removeItem(at: markdownURL)
            }
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sortedEntries) else { return }
        try? data.write(to: jsonURL, options: .atomic)
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
