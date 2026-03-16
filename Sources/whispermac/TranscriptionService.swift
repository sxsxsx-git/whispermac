import Foundation

struct TranscriptionService {
    private let audioPreprocessorPath = "/usr/bin/afconvert"

    func transcribe(
        inputURL: URL,
        outputDirectory: URL,
        whisperCLIPath: String,
        modelPath: String,
        formats: Set<OutputFormat>,
        onStageChange: @escaping @Sendable (TranscriptionStage) async -> Void,
        onLog: @escaping @Sendable (String) async -> Void,
        onTranscriptionProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> TranscriptionReport {
        let startedAt = Date()
        await onStageChange(.preparing)
        await onLog(L.tr("transcription.prepare_file", inputURL.path))
        await onLog(L.tr("transcription.output_directory", outputDirectory.path))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)

        let wavURL = OutputPaths.temporaryWAVURL(for: inputURL)
        defer {
            try? FileManager.default.removeItem(at: wavURL)
        }

        let audioPreparationArguments = [
            "-f", "WAVE",
            "-d", "LEI16@16000",
            "-c", "1",
            inputURL.path,
            wavURL.path,
        ]

        await onStageChange(.extractingAudio)
        await onLog(L.tr("transcription.start_audio_prep"))
        let audioPreparationStartedAt = Date()
        let audioPreparationResult = try await ShellCommand.run(
            executable: audioPreprocessorPath,
            arguments: audioPreparationArguments,
            onOutput: { stream, line in
                guard let filtered = CommandLogFilter.filteredLine(for: stream, tool: .audioPreprocessor, line: line) else {
                    return
                }
                await onLog("[afconvert \(stream.label)] \(filtered)")
            }
        )
        await onLog(L.tr("transcription.audio_prep_finished", Date().timeIntervalSince(audioPreparationStartedAt)))

        let outputPrefix = OutputPaths.outputPrefixURL(for: inputURL, outputDirectory: outputDirectory)
        var whisperArguments = [
            "-m", PathResolver.expandingTilde(modelPath),
            "-f", wavURL.path,
            "-l", "auto",
            "-of", outputPrefix.path,
            "-pp",
        ]
        whisperArguments.append(contentsOf: formats.sorted { $0.rawValue < $1.rawValue }.map(\.whisperArgument))

        await onStageChange(.transcribing)
        await onLog(L.tr("transcription.start_whisper"))
        let whisperStartedAt = Date()
        let whisperResult = try await ShellCommand.run(
            executable: whisperCLIPath,
            arguments: whisperArguments,
            onOutput: { stream, line in
                guard let filtered = CommandLogFilter.filteredLine(for: stream, tool: .whisper, line: line) else {
                    return
                }
                await onLog("[whisper \(stream.label)] \(filtered)")
                if let progress = parseWhisperProgress(from: line) {
                    await onTranscriptionProgress(progress)
                }
            }
        )
        await onLog(L.tr("transcription.whisper_finished", Date().timeIntervalSince(whisperStartedAt)))
        await onStageChange(.finished)

        let outputFiles = OutputPaths.outputFiles(for: inputURL, outputDirectory: outputDirectory, formats: formats)
        await onLog(L.tr("transcription.file_total_time", Date().timeIntervalSince(startedAt)))

        return TranscriptionReport(
            audioPreparationCommand: audioPreparationResult.command,
            whisperCommand: whisperResult.command,
            outputFiles: outputFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
        )
    }

    private func parseWhisperProgress(from line: String) -> Double? {
        guard let range = line.range(of: #"progress =\s*([0-9]{1,3})%"#, options: .regularExpression) else {
            return nil
        }

        let match = String(line[range])
        let percentText = match
            .replacingOccurrences(of: "progress =", with: "")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let percent = Double(percentText) else {
            return nil
        }

        return min(max(percent / 100.0, 0), 1)
    }
}
