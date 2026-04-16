import Foundation

enum StoreError: LocalizedError, Sendable {
    case directoryCreateFailed(String)
    case directoryListFailed(String)
    case readFailed(filename: String, detail: String)
    case decodeFailed(filename: String, preservedAs: String, detail: String)
    case quarantineFailed(filename: String, detail: String)
    case writeBlocked(filename: String)
    case saveFailed(filename: String, detail: String)
    case markdownSaveFailed(filename: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .directoryCreateFailed(let detail): return "Failed to create log directory: \(detail)"
        case .directoryListFailed(let detail): return "Failed to list log files: \(detail)"
        case .readFailed(let filename, let detail):
            return "Couldn't read \(filename): \(detail)"
        case .decodeFailed(let filename, let preservedAs, let detail):
            return "Couldn't read \(filename). The unreadable file was preserved as \(preservedAs). \(detail)"
        case .quarantineFailed(let filename, let detail):
            return "Couldn't preserve the unreadable file \(filename): \(detail)"
        case .writeBlocked(let filename):
            return "Saving is blocked until \(filename) is moved or fixed."
        case .saveFailed(let filename, let detail):
            return "Failed to save \(filename): \(detail)"
        case .markdownSaveFailed(let filename, let detail):
            return "Failed to save \(filename): \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .directoryCreateFailed:
            return "Check that the parent folder exists and is writable."
        case .directoryListFailed:
            return "Check that the log folder is still available and readable."
        case .readFailed:
            return "Check that the file exists, is readable, and is not locked by another process."
        case .decodeFailed:
            return "Review the preserved copy if you want to recover its contents manually."
        case .quarantineFailed:
            return "The app will not overwrite that day's log until the unreadable file is moved or fixed."
        case .writeBlocked:
            return "Move, rename, or repair the unreadable log file and then try again."
        case .saveFailed:
            return "Check disk space and folder permissions for the log directory."
        case .markdownSaveFailed:
            return "The JSON log was saved, but the Markdown export could not be written."
        }
    }
}

actor ActivityLogStore {
    private var logDirectory: URL
    private var blockedWriteDayKeys: Set<String> = []

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

    func hasStoredLogs() throws -> Bool {
        !(try storedLogDates()).isEmpty
    }

    func moveLogs(to url: URL) throws -> URL {
        let destinationDirectory = url.standardizedFileURL
        guard destinationDirectory != logDirectory else { return destinationDirectory }

        let filesToMove = try logFileURLs(in: logDirectory)
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

    func loadEntries(for date: Date) throws -> [LogEntry] {
        let fileURL = entriesFileURL(for: date)
        let dayKey = dayKey(for: date)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            blockedWriteDayKeys.remove(dayKey)
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            blockedWriteDayKeys.insert(dayKey)
            throw StoreError.readFailed(
                filename: fileURL.lastPathComponent,
                detail: error.localizedDescription
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let entries = try decoder.decode([LogEntry].self, from: data)
            blockedWriteDayKeys.remove(dayKey)
            return entries.sorted { $0.timestamp > $1.timestamp }
        } catch {
            // Quarantine renames the corrupt file, briefly leaving the original
            // filename absent. Actor serialization guarantees no concurrent call
            // to loadEntries or save can observe this intermediate state.
            let preservedJSONURL: URL
            do {
                preservedJSONURL = try quarantineUnreadableLog(for: date)
            } catch {
                blockedWriteDayKeys.insert(dayKey)
                throw StoreError.quarantineFailed(
                    filename: fileURL.lastPathComponent,
                    detail: error.localizedDescription
                )
            }
            blockedWriteDayKeys.remove(dayKey)
            throw StoreError.decodeFailed(
                filename: fileURL.lastPathComponent,
                preservedAs: preservedJSONURL.lastPathComponent,
                detail: error.localizedDescription
            )
        }
    }

    func save(entries: [LogEntry], for date: Date) throws {
        try ensureLogDirectoryExists()

        let dayKey = dayKey(for: date)
        let jsonURL = entriesFileURL(for: date)
        let markdownURL = markdownFileURL(for: date)
        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }

        if blockedWriteDayKeys.contains(dayKey) {
            throw StoreError.writeBlocked(filename: jsonURL.lastPathComponent)
        }

        if sortedEntries.isEmpty {
            try removeItemIfExists(
                at: jsonURL,
                error: .saveFailed(
                    filename: jsonURL.lastPathComponent,
                    detail: "The old JSON log could not be removed."
                )
            )
            try removeItemIfExists(
                at: markdownURL,
                error: .markdownSaveFailed(
                    filename: markdownURL.lastPathComponent,
                    detail: "The old Markdown log could not be removed."
                )
            )
            blockedWriteDayKeys.remove(dayKey)
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(sortedEntries)
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            throw StoreError.saveFailed(
                filename: jsonURL.lastPathComponent,
                detail: error.localizedDescription
            )
        }
        // JSON is the source of truth. A markdown-only failure should not
        // block future writes — surface it but keep going.
        blockedWriteDayKeys.remove(dayKey)
        try saveMarkdown(entries: sortedEntries, to: markdownURL, date: date)
    }

    func storedLogDates() throws -> [Date] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: logDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            )
        } catch {
            throw StoreError.directoryListFailed(error.localizedDescription)
        }

        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .filter { fileSize(for: $0) > 4 } // skip empty "[]" files
            .compactMap { WorkMonitorDates.date(fromStorageDayString: $0.deletingPathExtension().lastPathComponent) }
            .sorted(by: >)
    }

    private func entriesFileURL(for date: Date) -> URL {
        logDirectory.appendingPathComponent(WorkMonitorDates.storageDayString(for: date) + ".json")
    }

    private func markdownFileURL(for date: Date) -> URL {
        logDirectory.appendingPathComponent(WorkMonitorDates.storageDayString(for: date) + ".md")
    }

    private func logFileURLs(in directory: URL) throws -> [URL] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            throw StoreError.directoryListFailed(error.localizedDescription)
        }

        return files.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "json" || ext == "md"
        }
    }

    private func saveMarkdown(entries: [LogEntry], to url: URL, date: Date) throws {
        var markdown = "# Work Log — \(WorkMonitorDates.fullDateString(for: date))\n\n"
        for entry in entries {
            markdown += "- **\(WorkMonitorDates.timeString(for: entry.timestamp))** — \(entry.activity)\n"
        }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw StoreError.markdownSaveFailed(
                filename: url.lastPathComponent,
                detail: error.localizedDescription
            )
        }
    }

    private func dayKey(for date: Date) -> String {
        WorkMonitorDates.storageDayString(for: date)
    }

    /// Returns the file size in bytes, or 5 if the size can't be read.
    /// Returning 5 (above the empty-file threshold of 4) intentionally includes
    /// unreadable files so that `loadEntries` gets a chance to surface the real error.
    private func fileSize(for url: URL) -> Int {
        do {
            return try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        } catch {
            return 5
        }
    }

    private func removeItemIfExists(at url: URL, error storeError: StoreError) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw storeError
        }
    }

    private func quarantineUnreadableLog(for date: Date) throws -> URL {
        let jsonURL = entriesFileURL(for: date)
        let markdownURL = markdownFileURL(for: date)
        let suffix = ".corrupt-\(quarantineSuffix())"

        let preservedJSONURL = quarantinedURL(for: jsonURL, suffix: suffix)
        try FileManager.default.moveItem(at: jsonURL, to: preservedJSONURL)

        if FileManager.default.fileExists(atPath: markdownURL.path) {
            let preservedMarkdownURL = quarantinedURL(for: markdownURL, suffix: suffix)
            do {
                try FileManager.default.moveItem(at: markdownURL, to: preservedMarkdownURL)
            } catch {
                // The JSON source of truth is preserved above; failing to move the
                // auxiliary Markdown export should not prevent recovery.
            }
        }

        return preservedJSONURL
    }

    private func quarantinedURL(for originalURL: URL, suffix: String) -> URL {
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let fileExtension = originalURL.pathExtension
        return originalURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)\(suffix).\(fileExtension)")
    }

    /// Produces a short suffix like `T143012-A1B2C3D4` (time + UUID fragment).
    /// The day is already in the base filename, so we only need enough to
    /// disambiguate multiple quarantines on the same day.
    private func quarantineSuffix() -> String {
        let f = DateFormatter()
        f.dateFormat = "HHmmss"
        return "T\(f.string(from: Date()))-\(UUID().uuidString.prefix(8))"
    }
}
