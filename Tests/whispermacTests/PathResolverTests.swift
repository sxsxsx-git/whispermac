import Foundation
import Testing
@testable import whispermac

@Test
func coreMLModelPathUsesEncoderSuffix() {
    let modelURL = URL(fileURLWithPath: "/tmp/Models/ggml-large-v3-turbo.bin")
    #expect(OutputPaths.coreMLModelURL(for: modelURL).path == "/tmp/Models/ggml-large-v3-turbo-encoder.mlmodelc")
}

@Test
func outputFilesMatchSelectedFormats() {
    let inputURL = URL(fileURLWithPath: "/tmp/demo.mp4")
    let outputDirectory = URL(fileURLWithPath: "/tmp/out")
    let files = OutputPaths.outputFiles(for: inputURL, outputDirectory: outputDirectory, formats: [.srt, .txt])
    #expect(files.map { $0.lastPathComponent } == ["demo.srt", "demo.txt"])
}

@Test
func resolveWhisperCLIPathFallsBackToKnownLocalArtifact() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let whisperCLIURL = root.appending(path: ".build-tools/whisper.cpp/build/bin/whisper-cli")
    try FileManager.default.createDirectory(at: whisperCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: whisperCLIURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: whisperCLIURL.path)

    let resolved = PathResolver.resolveWhisperCLIPath(
        "/missing/whisper-cli",
        searchRoots: [root]
    )

    #expect(resolved == whisperCLIURL.path)
}

@Test
func resolveWhisperCLIPathDoesNotTreatDirectoryAsExecutable() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let directoryOnlyURL = root.appending(path: "usr/bin", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryOnlyURL, withIntermediateDirectories: true)

    let whisperCLIURL = root.appending(path: ".build-tools/whisper.cpp/build/bin/whisper-cli")
    try FileManager.default.createDirectory(at: whisperCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: whisperCLIURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: whisperCLIURL.path)

    let resolved = PathResolver.resolveWhisperCLIPath(
        directoryOnlyURL.path,
        searchRoots: [root]
    )

    #expect(resolved == whisperCLIURL.path)
}

@Test
func resolveModelPathSearchesInsideProvidedDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let nestedDirectory = root.appending(path: "Downloads/whisper-models", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

    let modelURL = nestedDirectory.appending(path: "ggml-base.en.bin")
    FileManager.default.createFile(atPath: modelURL.path, contents: Data())

    let resolved = PathResolver.resolveModelPath(root.appending(path: "Downloads").path)

    #expect(URL(fileURLWithPath: resolved).standardizedFileURL.path == modelURL.standardizedFileURL.path)
}

@Test
func resolveModelPathUsesModelsDirectoryNextToWhisperCLI() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let whisperCLIURL = root.appending(path: "Vendor/whisper.cpp/build/bin/whisper-cli")
    try FileManager.default.createDirectory(at: whisperCLIURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: whisperCLIURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: whisperCLIURL.path)

    let modelURL = root.appending(path: "Vendor/whisper.cpp/models/ggml-large-v3-turbo.bin")
    try FileManager.default.createDirectory(at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: modelURL.path, contents: Data())

    let resolved = PathResolver.resolveModelPath(
        "",
        whisperCLIPath: whisperCLIURL.path,
        searchRoots: [root]
    )

    #expect(resolved == modelURL.path)
}
