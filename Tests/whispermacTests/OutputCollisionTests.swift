import Foundation
import Testing
@testable import whispermac

private actor BumpCollector {
    var names: [String] = []
    func add(_ name: String) {
        names.append(name)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test
func uniqueOutputPrefixKeepsBaseStemWhenNothingExists() throws {
    let outputDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: outputDirectory) }

    let prefix = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/media/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.txt, .srt],
        takenPrefixes: []
    )

    #expect(prefix.path == outputDirectory.appending(path: "report").path)
}

@Test
func uniqueOutputPrefixBumpsPastExistingOutputs() throws {
    let outputDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    FileManager.default.createFile(atPath: outputDirectory.appending(path: "report.txt").path, contents: Data())

    let first = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.txt],
        takenPrefixes: []
    )
    #expect(first.lastPathComponent == "report-1")

    FileManager.default.createFile(atPath: outputDirectory.appending(path: "report-1.txt").path, contents: Data())

    let second = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.txt],
        takenPrefixes: []
    )
    #expect(second.lastPathComponent == "report-2")
}

@Test
func uniqueOutputPrefixKeepsBaseWhenOnlyUnselectedFormatExists() throws {
    let outputDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    FileManager.default.createFile(atPath: outputDirectory.appending(path: "report.txt").path, contents: Data())

    let prefix = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.srt],
        takenPrefixes: []
    )

    #expect(prefix.lastPathComponent == "report")
}

@Test
func uniqueOutputPrefixBumpsOnCaseInsensitiveFileCollision() throws {
    let outputDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    FileManager.default.createFile(atPath: outputDirectory.appending(path: "Report.txt").path, contents: Data())

    let prefix = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.txt],
        takenPrefixes: []
    )

    #expect(prefix.lastPathComponent == "report-1")
}

@Test
func uniqueOutputPrefixTreatsDirectoryWithOutputNameAsCollision() throws {
    let outputDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    try FileManager.default.createDirectory(at: outputDirectory.appending(path: "report.txt"), withIntermediateDirectories: true)

    let prefix = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.txt],
        takenPrefixes: []
    )

    #expect(prefix.lastPathComponent == "report-1")
}

@Test
func uniqueOutputPrefixBumpsWhenPrefixTakenEarlierInBatch() {
    let outputDirectory = URL(fileURLWithPath: "/tmp/out")

    let first = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/a/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.txt],
        takenPrefixes: []
    )
    let second = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/b/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.txt],
        takenPrefixes: [first.path]
    )
    #expect(first.lastPathComponent == "report")
    #expect(second.lastPathComponent == "report-1")
}

@Test
func uniqueOutputPrefixTakenPrefixesCompareCaseInsensitively() {
    let prefix = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/b/report.mp4"),
        outputDirectory: URL(fileURLWithPath: "/tmp/out"),
        formats: [.txt],
        takenPrefixes: ["/tmp/out/REPORT"]
    )

    #expect(prefix.lastPathComponent == "report-1")
}

@Test
func uniqueOutputPrefixBumpsWhenJsonAndVttOutputsExist() throws {
    let outputDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    FileManager.default.createFile(atPath: outputDirectory.appending(path: "report.json").path, contents: Data())
    FileManager.default.createFile(atPath: outputDirectory.appending(path: "report.vtt").path, contents: Data())

    let prefix = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.json, .vtt],
        takenPrefixes: []
    )

    #expect(prefix.lastPathComponent == "report-1")
}

@Test
func uniqueOutputPrefixKeepsBaseWhenOnlyUnselectedNewFormatExists() throws {
    let outputDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    FileManager.default.createFile(atPath: outputDirectory.appending(path: "report.txt").path, contents: Data())

    let prefix = OutputPaths.uniqueOutputPrefix(
        for: URL(fileURLWithPath: "/tmp/report.mp4"),
        outputDirectory: outputDirectory,
        formats: [.json, .vtt],
        takenPrefixes: []
    )

    #expect(prefix.lastPathComponent == "report")
}

@Test
func outputFilesDeriveVttAndJsonExtensionsInSortedOrder() {
    let files = OutputPaths.outputFiles(prefix: URL(fileURLWithPath: "/tmp/out/report"), formats: [.vtt, .json])

    #expect(files.map { $0.lastPathComponent } == ["report.json", "report.vtt"])
}

@Test
func outputFilesDeriveFromAssignedPrefix() {
    let files = OutputPaths.outputFiles(prefix: URL(fileURLWithPath: "/tmp/out/report-1"), formats: [.srt, .txt])
    #expect(files.map { $0.lastPathComponent } == ["report-1.srt", "report-1.txt"])
}

@Test
func batchPrefixSeamAssignsDistinctPrefixesForSameStemInputs() async throws {
    let outputDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: outputDirectory) }
    let inputs = [
        BatchTranscriptionInput(inputURL: URL(fileURLWithPath: "/tmp/a/report.mp4"), outputDirectory: outputDirectory),
        BatchTranscriptionInput(inputURL: URL(fileURLWithPath: "/tmp/b/report.mp4"), outputDirectory: outputDirectory),
    ]
    let bumps = BumpCollector()

    let prefixes = await TranscriptionService.uniqueOutputPrefixes(for: inputs, formats: [.txt], onBump: { name in
        await bumps.add(name)
    })

    #expect(prefixes[0].lastPathComponent == "report")
    #expect(prefixes[1].lastPathComponent == "report-1")

    let arguments = WhisperInvocation.arguments(
        modelPath: "/fake/model.bin",
        wavPaths: inputs.map { $0.inputURL.path },
        outputPrefixes: prefixes.map(\.path),
        formats: [.txt]
    )
    let ofPrefixes = arguments.indices.filter { arguments[$0] == "-of" }.map { arguments[$0 + 1] }
    #expect(ofPrefixes == prefixes.map(\.path))
    #expect(ofPrefixes[0] != ofPrefixes[1])

    #expect(await bumps.names == ["report-1"])
}

@Test(arguments: ["en", "zh-hans", "ja"])
func outputRenamedLogKeyIsLocalizedInEveryBundle(language: String) throws {
    let lprojPath = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
    let bundle = try #require(Bundle(path: lprojPath))
    let value = bundle.localizedString(forKey: "log.output_renamed", value: "", table: "Localizable")
    #expect(!value.isEmpty)
    #expect(value.contains("%@"))
}
