import Foundation

enum ShellOutputStream: Sendable {
    case stdout
    case stderr

    var label: String {
        switch self {
        case .stdout:
            return "stdout"
        case .stderr:
            return "stderr"
        }
    }
}

enum ShellCommandError: LocalizedError {
    case missingExecutable(String)
    case failedToStart(String)
    case nonZeroExit(command: String, code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name):
            return "找不到可执行文件: \(name)"
        case .failedToStart(let command):
            return "命令启动失败: \(command)"
        case .nonZeroExit(let command, let code, let stderr):
            let detail = stderr.isEmpty ? "无错误输出" : stderr
            return "命令执行失败(\(code)): \(command)\n\(detail)"
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "whispermac.shell-output")
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    func appendStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.sync {
            stdoutData.append(data)
        }
    }

    func appendStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.sync {
            stderrData.append(data)
        }
    }

    func appendLines(_ data: Data, to stream: ShellOutputStream) -> [String] {
        guard !data.isEmpty else { return [] }

        return queue.sync {
            let chunk = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")

            switch stream {
            case .stdout:
                stdoutData.append(data)
                stdoutBuffer.append(chunk)
                return extractLines(from: &stdoutBuffer)
            case .stderr:
                stderrData.append(data)
                stderrBuffer.append(chunk)
                return extractLines(from: &stderrBuffer)
            }
        }
    }

    func flushPendingLines() -> [(ShellOutputStream, String)] {
        queue.sync {
            var pending: [(ShellOutputStream, String)] = []

            let stdoutTail = stdoutBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stdoutTail.isEmpty {
                pending.append((.stdout, stdoutTail))
            }

            let stderrTail = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderrTail.isEmpty {
                pending.append((.stderr, stderrTail))
            }

            stdoutBuffer.removeAll(keepingCapacity: false)
            stderrBuffer.removeAll(keepingCapacity: false)

            return pending
        }
    }

    func snapshot() -> (stdout: String, stderr: String) {
        queue.sync {
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            return (stdout, stderr)
        }
    }

    private func extractLines(from buffer: inout String) -> [String] {
        var lines: [String] = []

        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                lines.append(line)
            }
            buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
        }

        return lines
    }
}

struct ShellCommandResult: Sendable {
    let command: String
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var combinedOutput: String {
        [stdout, stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ShellCommand {
    static func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        onOutput: (@Sendable (ShellOutputStream, String) async -> Void)? = nil
    ) async throws -> ShellCommandResult {
        let resolved = PathResolver.resolveExecutablePath(executable).isEmpty ? PathResolver.expandingTilde(executable) : PathResolver.resolveExecutablePath(executable)
        guard FileManager.default.isExecutableFile(atPath: resolved) else {
            throw ShellCommandError.missingExecutable(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let collector = OutputCollector()

        let command = ([resolved] + arguments).map(quoted).joined(separator: " ")

        return try await withCheckedThrowingContinuation { continuation in
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let lines = collector.appendLines(data, to: .stdout)
                guard let onOutput else { return }
                for line in lines {
                    Task {
                        await onOutput(.stdout, line)
                    }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let lines = collector.appendLines(data, to: .stderr)
                guard let onOutput else { return }
                for line in lines {
                    Task {
                        await onOutput(.stderr, line)
                    }
                }
            }

            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let stdoutLines = collector.appendLines(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), to: .stdout)
                let stderrLines = collector.appendLines(stderrPipe.fileHandleForReading.readDataToEndOfFile(), to: .stderr)
                if let onOutput {
                    for line in stdoutLines {
                        Task {
                            await onOutput(.stdout, line)
                        }
                    }
                    for line in stderrLines {
                        Task {
                            await onOutput(.stderr, line)
                        }
                    }
                    for (stream, line) in collector.flushPendingLines() {
                        Task {
                            await onOutput(stream, line)
                        }
                    }
                }
                let output = collector.snapshot()

                let result = ShellCommandResult(
                    command: command,
                    stdout: output.stdout,
                    stderr: output.stderr,
                    exitCode: process.terminationStatus
                )

                if process.terminationStatus == 0 {
                    continuation.resume(returning: result)
                } else {
                    let errorOutput = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? result.combinedOutput
                        : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: ShellCommandError.nonZeroExit(
                        command: command,
                        code: process.terminationStatus,
                        stderr: errorOutput
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ShellCommandError.failedToStart(command))
            }
        }
    }

    private static func quoted(_ value: String) -> String {
        if value.contains(where: \.isWhitespace) {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return value
    }
}
