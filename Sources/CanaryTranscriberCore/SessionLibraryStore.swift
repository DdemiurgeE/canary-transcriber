import Foundation

/// Single owner for the persisted session library (the "Library" list survives app relaunch).
public final class SessionLibraryStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let directory = directoryURL ?? Self.defaultDirectory(fileManager: fileManager)
        self.fileURL = directory.appendingPathComponent("library.json")
    }

    public func load() -> [SessionRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SessionRecord].self, from: data)) ?? []
    }

    public func save(_ sessions: [SessionRecord]) {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sessions)
            let tempURL = fileURL.appendingPathExtension("tmp")
            try data.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            // Best-effort persistence: the in-memory library stays authoritative for this run.
        }
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CanaryTranscriber", isDirectory: true)
    }
}
