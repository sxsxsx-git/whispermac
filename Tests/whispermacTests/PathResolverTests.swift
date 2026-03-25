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
func invalidStoredExecutableFallsBackToGuessedPath() {
    let guessed = "/bin/sh"
    let recovered = PathResolver.preferredExecutablePath(
        storedValue: "/tmp/does-not-exist/whisper-cli",
        guessedValue: guessed
    )
    #expect(recovered == guessed)
}

@Test
func bundledCLIShouldNotUseDownloadedRuntimeLocation() {
    let guessed = PathResolver.guessDefaults().whisperCLIPath
    #expect(!guessed.contains("/Library/Application Support/WhisperMac/runtime/bin/whisper-cli"))
}

@Test
func invalidStoredModelFallsBackToGuessedPath() throws {
    let guessedURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    FileManager.default.createFile(atPath: guessedURL.path, contents: Data())
    defer { try? FileManager.default.removeItem(at: guessedURL) }

    let recovered = PathResolver.preferredFilePath(
        storedValue: "/tmp/does-not-exist/ggml-large-v3-turbo.bin",
        guessedValue: guessedURL.path
    )
    #expect(recovered == guessedURL.path)
}
