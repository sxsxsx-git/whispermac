import Foundation

/// One local diagnostic file per batch. Logging failures must not stop transcription.
actor TranscriptionRunLog {
    nonisolated let url: URL
    private let handle: FileHandle

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/WhisperMac", directoryHint: .isDirectory)) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "transcription-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    deinit { try? handle.close() }

    func append(_ line: String) {
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }

    static func run(
        executable: String,
        arguments: [String],
        log: TranscriptionRunLog?,
        onOutput: @escaping @Sendable (ShellOutputStream, String) async -> Void
    ) async throws -> ShellCommandResult {
        // JSON preserves exact arguments, including spaces, quotes, and newlines.
        if let data = try? JSONEncoder().encode([executable] + arguments) {
            await log?.append("\(Date().ISO8601Format()) command: \(String(decoding: data, as: UTF8.self))")
        }
        do {
            let result = try await ShellCommand.run(executable: executable, arguments: arguments) { stream, line in
                await log?.append("[\(stream.label)] \(line)")
                await onOutput(stream, line)
            }
            await log?.append("\(Date().ISO8601Format()) exit: \(result.exitCode)")
            return result
        } catch {
            await log?.append("\(Date().ISO8601Format()) error: \(error)")
            throw error
        }
    }
}
