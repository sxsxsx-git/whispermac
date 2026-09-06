import Foundation
import Testing
@testable import whispermac

/// Fixture lines below are real whisper-cli stdout/stderr captures from the bundled
/// runtime (dist/WhisperMac.app/Contents/Resources/runtime/bin/whisper-cli, ggml-large-v3-turbo):
///   $ whisper-cli -m model.bin -f tiny1.wav -l auto -pp -osrt 1>out.txt 2>err.txt
/// Segment lines on stdout use "[HH:MM:SS.mmm --> HH:MM:SS.mmm]" followed by two
/// format spaces plus the raw whisper text (which itself usually starts with a space).
@Suite
struct LiveSegmentParserTests {
    @Test
    func parsesRealSingleFileSegmentLine() {
        let segment = LiveSegmentParser.parse("[00:00:00.000 --> 00:00:00.340]   Hello.")
        #expect(segment != nil)
        #expect(segment?.start == 0.0)
        #expect(segment?.end == 0.34)
        #expect(segment?.text == "Hello.")
    }

    @Test
    func parsesRealTwoFileBatchSegmentLine() {
        let segment = LiveSegmentParser.parse(
            "[00:00:00.000 --> 00:00:03.920]   Second file, Whisper streaming segments should appear here."
        )
        #expect(segment != nil)
        #expect(segment?.start == 0.0)
        #expect(segment?.end == 3.92)
        #expect(segment?.text == "Second file, Whisper streaming segments should appear here.")
    }

    @Test
    func parsesRealTranslateRunSegmentLine() {
        // --translate changes only the text content; the stdout shape is identical.
        let segment = LiveSegmentParser.parse(
            "[00:00:00.000 --> 00:00:30.000]   . Bonjour le monde. Ceci est un test de transcription en direct avec traduction."
        )
        #expect(segment != nil)
        #expect(segment?.start == 0.0)
        #expect(segment?.end == 30.0)
        #expect(segment?.text == ". Bonjour le monde. Ceci est un test de transcription en direct avec traduction.")
    }

    @Test
    func parsesHourCarryingTimestamps() {
        let segment = LiveSegmentParser.parse("[01:02:03.500 --> 01:02:04.250]   Later words.")
        #expect(segment != nil)
        #expect(segment?.start == 3723.5)
        #expect(segment?.end == 3724.25)
        #expect(segment?.text == "Later words.")
    }

    @Test
    func preservesInternalMultiSpaceInText() {
        let segment = LiveSegmentParser.parse("[00:00:01.000 --> 00:00:02.000]   spaced  out  text")
        #expect(segment?.text == "spaced  out  text")
    }

    @Test
    func toleratesMinutesOnlyTimestampVariant() {
        // Defensive variant (MM:SS.mmm) never observed with the bundled build,
        // but unambiguous enough to accept.
        let segment = LiveSegmentParser.parse("[00:00.000 --> 00:03.000] text")
        #expect(segment != nil)
        #expect(segment?.start == 0.0)
        #expect(segment?.end == 3.0)
        #expect(segment?.text == "text")
    }

    @Test
    func parsesTrailingWhitespaceTrimmed() {
        let segment = LiveSegmentParser.parse("[00:00:00.000 --> 00:00:01.000]   padded text   ")
        #expect(segment?.text == "padded text")
    }

    @Test
    func rejectsRealStderrProcessingLine() {
        let line = "main: processing 'tiny1.wav' (7936 samples, 0.5 sec), 4 threads, 1 processors, 5 beams + best of 5, lang = auto, task = transcribe, timestamps = 1 ..."
        #expect(LiveSegmentParser.parse(line) == nil)
    }

    @Test
    func rejectsRealProgressLine() {
        #expect(LiveSegmentParser.parse("whisper_print_progress_callback: progress = 100%") == nil)
    }

    @Test
    func rejectsRealAudioReadLine() {
        #expect(LiveSegmentParser.parse("read_audio_data: reading audio data from 'tiny1.wav' ...") == nil)
    }

    @Test
    func rejectsRandomTextAndBlankLines() {
        #expect(LiveSegmentParser.parse("") == nil)
        #expect(LiveSegmentParser.parse("   ") == nil)
        #expect(LiveSegmentParser.parse("system_info: n_threads = 4 / 10 | WHISPER : COREML = 1") == nil)
        #expect(LiveSegmentParser.parse("just some words") == nil)
    }

    @Test
    func rejectsTimestampishLinesThatAreNotSegments() {
        #expect(LiveSegmentParser.parse("[00:00:00.000 --> 00:00:00.340]") == nil)
        #expect(LiveSegmentParser.parse("[00:00:00.000 --> 00:00:00.340]   ") == nil)
        #expect(LiveSegmentParser.parse("[00:00:00 not a segment") == nil)
        #expect(LiveSegmentParser.parse("[00:00:00.000]   no arrow") == nil)
        #expect(LiveSegmentParser.parse("[00:00:00.000 --> later]  junk") == nil)
        #expect(LiveSegmentParser.parse("[whisper_init_state: kv self size  =   10.49 MB]") == nil)
    }

    @Test
    func parserLeavesIDAssignmentToCaller() {
        let segment = LiveSegmentParser.parse("[00:00:00.000 --> 00:00:00.340]   Hello.")
        #expect(segment?.id == 0)
    }
}

@Suite
struct AppendCappedTests {
    @Test
    func appendsIntoEmptyList() {
        let segment = TranscriptSegment(id: 0, start: 1, end: 2, text: "First.")
        let appended = TranscriptPreview.appendCapped(segment, to: [], limit: 3)
        #expect(appended == [segment])
    }

    @Test
    func assignsMonotonicallyIncreasingIDs() {
        var segments: [TranscriptSegment] = []
        for index in 0..<5 {
            let raw = TranscriptSegment(id: 0, start: Double(index), end: Double(index) + 1, text: "Text \(index)")
            segments = TranscriptPreview.appendCapped(raw, to: segments, limit: 300)
        }
        #expect(segments.map(\.id) == [0, 1, 2, 3, 4])
    }

    @Test
    func keepsLastNWhenAppendingPastLimit() {
        var segments: [TranscriptSegment] = []
        for index in 0..<10 {
            let raw = TranscriptSegment(id: 0, start: Double(index), end: Double(index) + 1, text: "Text \(index)")
            segments = TranscriptPreview.appendCapped(raw, to: segments, limit: 3)
        }
        #expect(segments.count == 3)
        #expect(segments.map(\.text) == ["Text 7", "Text 8", "Text 9"])
    }

    @Test
    func idsRemainUniqueAfterCapEviction() {
        var segments: [TranscriptSegment] = []
        for index in 0..<400 {
            let raw = TranscriptSegment(id: 0, start: Double(index), end: Double(index) + 1, text: "Text \(index)")
            segments = TranscriptPreview.appendCapped(raw, to: segments, limit: 300)
        }
        #expect(segments.count == 300)
        #expect(Set(segments.map(\.id)).count == 300)
        #expect(segments.first?.id == 100)
        #expect(segments.last?.id == 399)
    }

    @Test
    func zeroLimitYieldsEmptyArray() {
        let segment = TranscriptSegment(id: 0, start: 1, end: 2, text: "First.")
        #expect(TranscriptPreview.appendCapped(segment, to: [], limit: 0) == [])
    }

    @Test
    func defaultLiveLimitIsPerformanceSafe() {
        #expect(TranscriptPreview.liveSegmentLimit == 300)
    }
}

/// Integration check for the live pipeline: a fake whisper-cli prints a real
/// captured stdout segment line; transcribeBatch must deliver it via onSegment
/// while keeping log filtering untouched (stdout still dropped, stderr passed).
@Suite
struct LiveSegmentPipelineTests {
    private actor Recorder {
        var logLines: [String] = []
        var segments: [TranscriptSegment] = []
        var progressValues: [Double] = []
        func recordLog(_ line: String) { logLines.append(line) }
        func recordSegment(_ segment: TranscriptSegment) { segments.append(segment) }
        func recordProgress(_ value: Double) { progressValues.append(value) }
    }

    @Test
    func transcribeBatchRoutesStdoutSegmentsThroughOnSegmentWithoutChangingLogs() async throws {
        let fileManager = FileManager.default
        let inputURL = fileManager.temporaryDirectory
            .appending(path: "whispermac-live-input-\(UUID().uuidString).wav")
        try Self.tinyWAVData().write(to: inputURL)
        defer { try? fileManager.removeItem(at: inputURL) }

        let outputDirectory = fileManager.temporaryDirectory
            .appending(path: "whispermac-live-output-\(UUID().uuidString)")
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: outputDirectory) }

        let scriptURL = fileManager.temporaryDirectory
            .appending(path: "whispermac-fake-whisper-cli-\(UUID().uuidString).sh")
        try """
        #!/bin/sh
        echo "[00:00:00.000 --> 00:00:00.340]   Hello."
        echo "whisper_print_progress_callback: progress = 50%" >&2
        exit 0
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? fileManager.removeItem(at: scriptURL) }

        let recorder = Recorder()
        let service = TranscriptionService()
        _ = try await service.transcribeBatch(
            inputs: [BatchTranscriptionInput(inputURL: inputURL, outputDirectory: outputDirectory)],
            whisperCLIPath: scriptURL.path,
            modelPath: "/dev/null",
            formats: [.srt],
            sourceLanguage: WhisperLanguage.autoCode,
            translatesToEnglish: false,
            onInputStageChange: { _, _ in },
            onStageChange: { _ in },
            onLog: { line in await recorder.recordLog(line) },
            onTranscriptionProgress: { value in await recorder.recordProgress(value) },
            onSegment: { segment in await recorder.recordSegment(segment) }
        )

        let segments = await recorder.segments
        #expect(segments.count == 1)
        #expect(segments.first?.start == 0.0)
        #expect(segments.first?.end == 0.34)
        #expect(segments.first?.text == "Hello.")

        // Filtering behavior is unchanged: the stdout segment never reaches the log.
        let logs = await recorder.logLines
        #expect(!logs.contains { $0.contains("[whisper stdout]") && $0.contains("Hello.") })
        // The stderr path is unchanged: filtered stderr line is logged as before.
        #expect(logs.contains { $0 == "[whisper stderr] whisper_print_progress_callback: progress = 50%" })
        let progressValues = await recorder.progressValues
        #expect(progressValues == [0.5])
    }

    /// Minimal valid 16 kHz mono PCM WAV (0.1 s of silence) so afconvert succeeds.
    private static func tinyWAVData() -> Data {
        let sampleRate = 16_000
        let samples = [Int16](repeating: 0, count: sampleRate / 10)
        let dataSize = samples.count * MemoryLayout<Int16>.size

        var data = Data()
        func appendBytes(of value: some FixedWidthInteger) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func appendString(_ string: String) {
            data.append(contentsOf: string.utf8)
        }

        appendString("RIFF")
        appendBytes(of: UInt32(36 + dataSize))
        appendString("WAVE")
        appendString("fmt ")
        appendBytes(of: UInt32(16))
        appendBytes(of: UInt16(1))
        appendBytes(of: UInt16(1))
        appendBytes(of: UInt32(sampleRate))
        appendBytes(of: UInt32(sampleRate * 2))
        appendBytes(of: UInt16(2))
        appendBytes(of: UInt16(16))
        appendString("data")
        appendBytes(of: UInt32(dataSize))
        for sample in samples {
            appendBytes(of: sample)
        }
        return data
    }
}
