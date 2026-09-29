import Foundation
import Testing
@testable import whispermac

@Suite
struct RuntimeInstallerReplacementTests {
    @Test
    func cancellationImmediatelyBeforeCommitPreservesInstalledModel() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "model.bin")
        let source = directory.appending(path: "download.tmp")
        try Data("old model".utf8).write(to: destination)
        try Data("new model".utf8).write(to: source)

        #expect(throws: CancellationError.self) {
            try RuntimeInstaller.replaceItem(at: destination, with: source, executable: false) {
                throw CancellationError()
            }
        }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "old model")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["model.bin"])
    }

    @Test
    func successfulReplacementInstallsNewFileAndRemovesOldContents() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "model.bin")
        let source = directory.appending(path: "download.tmp")
        try Data("old model".utf8).write(to: destination)
        try Data("new model".utf8).write(to: source)

        try RuntimeInstaller.replaceItem(at: destination, with: source, executable: false)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "new model")
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func installAtNewDestinationCreatesFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "model.bin")
        let source = directory.appending(path: "download.tmp")
        try Data("new model".utf8).write(to: source)

        try RuntimeInstaller.replaceItem(at: destination, with: source, executable: false)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "new model")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
