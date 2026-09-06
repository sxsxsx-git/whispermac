import Foundation
import Testing
@testable import whispermac

private func makeEntry(
    inputFileName: String = "interview.mp4",
    completedAt: Date = Date()
) -> HistoryEntry {
    HistoryEntry(
        id: UUID().uuidString,
        inputFileName: inputFileName,
        inputFilePath: "/tmp/inputs/\(inputFileName)",
        outputDirectoryPath: "/tmp/outputs",
        outputFilePaths: ["/tmp/outputs/\(inputFileName).txt", "/tmp/outputs/\(inputFileName).srt"],
        completedAt: completedAt,
        durationSeconds: 12.5
    )
}

private func makeReport(outputPaths: [String]) -> TranscriptionReport {
    TranscriptionReport(
        audioPreparationCommand: "/usr/bin/afconvert -f WAVE in.mp4 out.wav",
        whisperCommand: "whisper-cli -m model.bin",
        outputFiles: outputPaths.map { URL(fileURLWithPath: $0) }
    )
}

private func makeTemporaryStore() throws -> (store: TranscriptionHistoryStore, directory: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "whispermac-history-\(UUID().uuidString)", directoryHint: .isDirectory)
    return (TranscriptionHistoryStore(directory: directory), directory)
}

@Test
func defaultStoreUsesApplicationSupportWhisperMacDirectory() {
    let store = TranscriptionHistoryStore()
    #expect(store.directory == PathResolver.applicationSupportRoot)
    #expect(store.historyFileURL.lastPathComponent == "history.json")
    #expect(store.historyFileURL.deletingLastPathComponent() == PathResolver.applicationSupportRoot)
}

@Test
func loadReturnsEmptyForMissingFile() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(store.load().isEmpty)
}

@Test
func loadReturnsEmptyForCorruptJSON() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{ definitely not json ".utf8).write(to: store.historyFileURL)

    #expect(store.load().isEmpty)
}

@Test
func recordThenLoadRoundTripsNewestFirst() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let oldest = makeEntry(inputFileName: "old.mp4", completedAt: base)
    let middle = makeEntry(inputFileName: "middle.mp4", completedAt: base.addingTimeInterval(60))
    let newest = makeEntry(inputFileName: "new.mp4", completedAt: base.addingTimeInterval(120))

    try store.record([oldest, middle, newest])

    let loaded = store.load()
    #expect(loaded.count == 3)
    #expect(loaded[0].id == newest.id)
    #expect(loaded[1].id == middle.id)
    #expect(loaded[2].id == oldest.id)
    #expect(loaded[0] == newest)
    #expect(loaded[2] == oldest)
}

@Test
func loadKeepsWrittenOrderForEntriesSharingTimestamps() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let shared = Date(timeIntervalSince1970: 1_700_000_000)
    try store.record([
        makeEntry(inputFileName: "first.mp4", completedAt: shared),
        makeEntry(inputFileName: "second.mp4", completedAt: shared),
    ])

    let loaded = store.load()
    #expect(loaded.map(\.inputFileName) == ["first.mp4", "second.mp4"])
}

@Test
func recordAppendsToExistingHistoryOnDisk() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let base = Date(timeIntervalSince1970: 1_700_000_000)
    try store.record([makeEntry(inputFileName: "monday.mp4", completedAt: base)])
    try store.record([makeEntry(inputFileName: "tuesday.mp4", completedAt: base.addingTimeInterval(3_600))])

    let loaded = store.load()
    #expect(loaded.count == 2)
    #expect(loaded[0].inputFileName == "tuesday.mp4")
    #expect(loaded[1].inputFileName == "monday.mp4")
}

@Test
func recordCapsHistoryAtOneHundredNewestEntries() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let entries = (0..<120).map { index in
        makeEntry(inputFileName: "clip-\(index).mp4", completedAt: base.addingTimeInterval(Double(index)))
    }
    try store.record(entries)

    let loaded = store.load()
    #expect(loaded.count == TranscriptionHistoryStore.entryLimit)
    // The 20 oldest entries are dropped; the newest survive, sorted newest-first.
    #expect(loaded.first?.inputFileName == "clip-119.mp4")
    #expect(loaded.last?.inputFileName == "clip-20.mp4")
}

@Test
func recordWritesAtomicallyAndLeavesNoTemporaryFilesBehind() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.record([makeEntry()])
    try store.record([makeEntry(inputFileName: "second.mp4", completedAt: Date().addingTimeInterval(1))])

    let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(contents == ["history.json"])
}

@Test
func clearRemovesHistoryFile() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.record([makeEntry()])
    #expect(!store.load().isEmpty)

    try store.clear()
    #expect(store.load().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.historyFileURL.path))
}

@Test
func clearToleratesMissingFile() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.clear()
    #expect(store.load().isEmpty)
}

@Test
func makeEntriesPairsReportsInputsAndDirectories() {
    let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let reports = [
        makeReport(outputPaths: ["/out/a.txt", "/out/a.srt"]),
        makeReport(outputPaths: ["/out/b.txt"]),
        makeReport(outputPaths: []),
    ]
    let inputFiles = [
        URL(fileURLWithPath: "/media/a.mp4"),
        URL(fileURLWithPath: "/media/b.m4a"),
        URL(fileURLWithPath: "/media/c.wav"),
    ]
    let outputDirectories = [
        URL(fileURLWithPath: "/out"),
        URL(fileURLWithPath: "/out2"),
        URL(fileURLWithPath: "/out3"),
    ]

    let entries = TranscriptionHistoryStore.makeEntries(
        reports: reports,
        inputFiles: inputFiles,
        outputDirectories: outputDirectories,
        durationSeconds: 42.5,
        completedAt: completedAt
    )

    #expect(entries.count == 3)
    #expect(entries[0].inputFileName == "a.mp4")
    #expect(entries[0].inputFilePath == "/media/a.mp4")
    #expect(entries[0].outputDirectoryPath == "/out")
    #expect(entries[0].outputFilePaths == ["/out/a.txt", "/out/a.srt"])
    #expect(entries[1].inputFileName == "b.m4a")
    #expect(entries[1].outputDirectoryPath == "/out2")
    #expect(entries[1].outputFilePaths == ["/out/b.txt"])
    #expect(entries[2].outputFilePaths.isEmpty)
    for entry in entries {
        #expect(entry.completedAt == completedAt)
        #expect(entry.durationSeconds == 42.5)
        #expect(!entry.id.isEmpty)
    }
    #expect(Set(entries.map(\.id)).count == 3)
}

@Test
func makeEntriesTrapsOnLengthMismatch() throws {
    // Death test: the child re-runs only this test with the marker environment
    // variable set, calls makeEntries with mismatched counts, and dies on the
    // precondition. Tests execute inside `swiftpm-testing-helper` (argv[0]),
    // so the child re-invokes that same helper directly with a single-test
    // filter — going through `swift test` again would deadlock on SwiftPM's
    // build lock held by the parent run.
    if ProcessInfo.processInfo.environment["WHISPERMAC_HISTORY_PRECONDITION_TEST"] != nil {
        _ = TranscriptionHistoryStore.makeEntries(
            reports: [makeReport(outputPaths: ["/out/a.txt"])],
            inputFiles: [
                URL(fileURLWithPath: "/media/a.mp4"),
                URL(fileURLWithPath: "/media/b.mp4"),
            ],
            outputDirectories: [URL(fileURLWithPath: "/out")],
            durationSeconds: 1
        )
        return
    }

    // Rebuild the helper invocation from this process's own arguments, minus
    // any filter the parent applied, plus a filter for this single test.
    var parentArguments = CommandLine.arguments
    if let filterIndex = parentArguments.firstIndex(of: "--filter"), filterIndex + 1 < parentArguments.count {
        parentArguments.removeSubrange(filterIndex...(filterIndex + 1))
    }
    var childArguments = parentArguments
    childArguments += ["--filter", "makeEntriesTrapsOnLengthMismatch"]

    let outputURL = FileManager.default.temporaryDirectory
        .appending(path: "whispermac-history-death-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: outputURL) }
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: outputURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: parentArguments[0])
    process.currentDirectoryURL = PathResolver.projectRoot
    process.arguments = Array(childArguments.dropFirst())
    var environment = ProcessInfo.processInfo.environment
    environment["WHISPERMAC_HISTORY_PRECONDITION_TEST"] = "1"
    process.environment = environment
    process.standardOutput = outputHandle
    process.standardError = outputHandle

    try process.run()
    process.waitUntilExit()
    try? outputHandle.close()

    let output = try String(contentsOf: outputURL, encoding: .utf8)
    #expect(process.terminationStatus != 0, "child should die on the precondition")
    #expect(output.contains("makeEntriesTrapsOnLengthMismatch() started"), "child must run this test, not fail to launch")
    #expect(output.contains("Precondition failed"), "child must trap inside makeEntries")
}

@Test
func codingPinsISO8601CompletedAtStrategy() throws {
    let (store, directory) = try makeTemporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let entry = makeEntry(completedAt: Date(timeIntervalSince1970: 1_760_000_000))
    try store.record([entry])

    // The raw JSON on disk stores completedAt as an ISO 8601 string.
    let rawData = try Data(contentsOf: store.historyFileURL)
    let objects = try #require(
        try JSONSerialization.jsonObject(with: rawData) as? [[String: Any]]
    )
    let rawCompletedAt = try #require(objects.first?["completedAt"] as? String)
    let isoFormatter = ISO8601DateFormatter()
    #expect(rawCompletedAt == isoFormatter.string(from: entry.completedAt))

    // Decoding through the store round-trips every field, including the date.
    let loaded = try #require(store.load().first)
    #expect(loaded == entry)
    #expect(loaded.completedAt == entry.completedAt)
}
