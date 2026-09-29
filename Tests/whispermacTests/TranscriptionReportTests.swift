import Foundation
import Testing
@testable import whispermac

@Suite
struct TranscriptionReportTests {
    @Test
    func emptyTextAndSubtitleOutputsHaveNoTranscriptContent() throws {
        let textURL = try temporaryFile(named: "empty.txt", contents: " \n\t")
        let srtURL = try temporaryFile(named: "empty.srt", contents: "\n  \n")
        defer { try? FileManager.default.removeItem(at: textURL.deletingLastPathComponent()) }
        #expect(!TranscriptContentDetector.containsContent(in: [textURL, srtURL]))
    }

    @Test
    func anyNonEmptyTranscriptOutputCountsAsSpeech() throws {
        let emptyURL = try temporaryFile(named: "empty.txt", contents: "")
        let transcriptURL = try temporaryFile(named: "speech.srt", contents: "1\n00:00:01,000 --> 00:00:02,000\n你好\n")
        defer {
            try? FileManager.default.removeItem(at: emptyURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: transcriptURL.deletingLastPathComponent())
        }
        #expect(TranscriptContentDetector.containsContent(in: [emptyURL, transcriptURL]))
    }

    @Test
    func jsonTranscriptArrayIsInspected() throws {
        let emptyURL = try temporaryFile(named: "empty.json", contents: #"{"transcription":[]}"#)
        let speechURL = try temporaryFile(named: "speech.json", contents: #"{"transcription":[{"text":"hello"}]}"#)
        defer {
            try? FileManager.default.removeItem(at: emptyURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: speechURL.deletingLastPathComponent())
        }
        #expect(!TranscriptContentDetector.containsContent(in: [emptyURL]))
        #expect(TranscriptContentDetector.containsContent(in: [speechURL]))
    }

    private func temporaryFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: name)
        try Data(contents.utf8).write(to: file)
        return file
    }
}
