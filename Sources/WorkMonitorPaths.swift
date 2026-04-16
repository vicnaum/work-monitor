import Foundation

enum WorkMonitorPaths {
    static let customLogDirectoryKey = "logDirectoryPath"

    static func defaultLogDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Work Monitor", isDirectory: true)
    }

    static func storedLogDirectory(userDefaults: UserDefaults = .standard) -> URL? {
        guard let path = userDefaults.string(forKey: customLogDirectoryKey),
              !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func resolvedLogDirectory(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) -> URL {
        storedLogDirectory(userDefaults: userDefaults) ?? defaultLogDirectory(fileManager: fileManager)
    }

    static func setStoredLogDirectory(_ url: URL?, userDefaults: UserDefaults = .standard) {
        if let url {
            userDefaults.set(url.standardizedFileURL.path, forKey: customLogDirectoryKey)
        } else {
            userDefaults.removeObject(forKey: customLogDirectoryKey)
        }
    }

    static func displayPath(for url: URL, fileManager: FileManager = .default) -> String {
        let path = url.standardizedFileURL.path
        let homePath = fileManager.homeDirectoryForCurrentUser.path

        guard path != homePath else { return "~" }
        guard path.hasPrefix(homePath + "/") else { return path }

        return "~/" + String(path.dropFirst(homePath.count + 1))
    }
}
