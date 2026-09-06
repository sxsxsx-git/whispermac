import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let inputFileName: String
    let inputFilePath: String
    let outputDirectoryPath: String
    let outputFilePaths: [String]
    let completedAt: Date
    let durationSeconds: Double
}

/// Records successful transcription batches as JSON under Application Support.
///
/// The store is a value type holding nothing but a directory URL, so it is
/// safe to hand across executors. `load()` never throws: a missing or corrupt
/// history file simply reads as an empty list. Dates are coded as ISO 8601
/// strings (pinned by `TranscriptionHistoryTests`).
struct TranscriptionHistoryStore: Sendable {
    static let entryLimit = 100

    let directory: URL

    init(directory: URL = PathResolver.applicationSupportRoot) {
        self.directory = directory
    }

    var historyFileURL: URL {
        directory.appending(path: "history.json")
    }

    /// Entries sorted newest-first; missing or corrupt files read as empty.
    func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyFileURL) else {
            return []
        }
        return Self.sortedNewestFirst(Self.decode(data))
    }

    /// Appends entries to the on-disk history, sorts newest-first, caps the
    /// file at `entryLimit` entries, and writes the result atomically.
    func record(_ entries: [HistoryEntry]) throws {
        guard !entries.isEmpty else { return }

        var all = load()
        all.append(contentsOf: entries)
        all = Self.sortedNewestFirst(all)
        if all.count > Self.entryLimit {
            all = Array(all.prefix(Self.entryLimit))
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeAtomically(Self.encode(all))
    }

    func clear() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return }
        try fileManager.removeItem(at: historyFileURL)
    }

    /// Pure mapping from a finished batch to history entries; pairs
    /// `reports[i]` with `inputFiles[i]` and `outputDirectories[i]`.
    static func makeEntries(
        reports: [TranscriptionReport],
        inputFiles: [URL],
        outputDirectories: [URL],
        durationSeconds: Double,
        completedAt: Date = Date()
    ) -> [HistoryEntry] {
        precondition(
            reports.count == inputFiles.count && inputFiles.count == outputDirectories.count,
            "reports, inputFiles, and outputDirectories must have equal counts"
        )

        return (0..<reports.count).map { index in
            HistoryEntry(
                id: UUID().uuidString,
                inputFileName: inputFiles[index].lastPathComponent,
                inputFilePath: inputFiles[index].path,
                outputDirectoryPath: outputDirectories[index].path,
                outputFilePaths: reports[index].outputFiles.map(\.path),
                completedAt: completedAt,
                durationSeconds: durationSeconds
            )
        }
    }

    /// Writes to a temporary sibling file, then swaps it in with
    /// `replaceItemAt` so readers never observe a partial history file.
    private func writeAtomically(_ data: Data) throws {
        let temporaryURL = directory.appending(path: "history-\(UUID().uuidString).json.tmp")
        do {
            try data.write(to: temporaryURL)
            if FileManager.default.fileExists(atPath: historyFileURL.path) {
                _ = try FileManager.default.replaceItemAt(historyFileURL, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: historyFileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// Newest-first; entries sharing a completion timestamp keep their
    /// relative order, so one batch's entries stay in input-file order.
    private static func sortedNewestFirst(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.completedAt != rhs.element.completedAt {
                    return lhs.element.completedAt > rhs.element.completedAt
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func encode(_ entries: [HistoryEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    private static func decode(_ data: Data) -> [HistoryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }
}
