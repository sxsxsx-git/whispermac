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
            return L.tr("error.missing_executable", name)
        case .failedToStart(let command):
            return L.tr("error.failed_to_start", command)
        case .nonZeroExit(let command, let code, let stderr):
            let detail = stderr.isEmpty ? L.tr("error.no_error_output") : stderr
            return L.tr("error.non_zero_exit", code, command, detail)
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "whispermac.shell-output")
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

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

private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var running = false
    private var cancelRequested = false
    private var openStreams: Set<ShellOutputStream> = [.stdout, .stderr]
    private var exitStatus: Int32?
    private var finalized = false

    init(process: Process) {
        self.process = process
    }

    func start() throws {
        try process.run()
        lock.lock()
        running = true
        lock.unlock()
    }

    func requestTermination() {
        lock.lock()
        cancelRequested = true
        let wasRunning = running
        lock.unlock()

        guard wasRunning, process.isRunning else { return }
        process.terminate()
    }

    var wasCancelRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelRequested
    }

    func closeStream(_ stream: ShellOutputStream) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        openStreams.remove(stream)
        return completionStatus()
    }

    func markExited(status: Int32) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        running = false
        exitStatus = status
        return completionStatus()
    }

    // Non-nil exactly once: when both pipes hit EOF and the process has exited.
    private func completionStatus() -> Int32? {
        guard !finalized, openStreams.isEmpty, let exitStatus else { return nil }
        finalized = true
        return exitStatus
    }
}

private enum ProcessExit: Sendable {
    case completed(ShellCommandResult)
    case nonZeroExit(ShellCommandError)
    case failedToStart(ShellCommandError)
    case terminatedByCancellation
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
        try Task.checkCancellation()

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
        let runningProcess = RunningProcess(process: process)

        let command = ([resolved] + arguments).map(quoted).joined(separator: " ")

        let emit = onOutput ?? { _, _ in }
        let (lineStream, lineContinuation) = AsyncStream.makeStream(of: (ShellOutputStream, String).self)
        let drain = Task {
            for await (stream, line) in lineStream {
                await emit(stream, line)
            }
        }

        return try await withTaskCancellationHandler {
            let exit: ProcessExit = await withCheckedContinuation { continuation in
                let finalize: @Sendable (Int32) -> Void = { status in
                    for (stream, line) in collector.flushPendingLines() {
                        lineContinuation.yield((stream, line))
                    }
                    lineContinuation.finish()

                    let output = collector.snapshot()
                    let result = ShellCommandResult(
                        command: command,
                        stdout: output.stdout,
                        stderr: output.stderr,
                        exitCode: status
                    )

                    if status == 0 {
                        continuation.resume(returning: .completed(result))
                    } else if runningProcess.wasCancelRequested {
                        continuation.resume(returning: .terminatedByCancellation)
                    } else {
                        let errorOutput = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? result.combinedOutput
                            : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: .nonZeroExit(ShellCommandError.nonZeroExit(
                            command: command,
                            code: status,
                            stderr: errorOutput
                        )))
                    }
                }

                let readers: [(FileHandle, ShellOutputStream)] = [
                    (stdoutPipe.fileHandleForReading, .stdout),
                    (stderrPipe.fileHandleForReading, .stderr),
                ]
                for (handle, stream) in readers {
                    handle.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else {
                            handle.readabilityHandler = nil
                            if let status = runningProcess.closeStream(stream) {
                                finalize(status)
                            }
                            return
                        }
                        for line in collector.appendLines(data, to: stream) {
                            lineContinuation.yield((stream, line))
                        }
                    }
                }

                process.terminationHandler = { process in
                    if let status = runningProcess.markExited(status: process.terminationStatus) {
                        finalize(status)
                    }
                }

                do {
                    try runningProcess.start()
                    if Task.isCancelled {
                        runningProcess.requestTermination()
                    }
                } catch {
                    for (handle, _) in readers {
                        handle.readabilityHandler = nil
                    }
                    lineContinuation.finish()
                    continuation.resume(returning: .failedToStart(ShellCommandError.failedToStart(command)))
                }
            }

            await drain.value

            if Task.isCancelled {
                throw CancellationError()
            }

            switch exit {
            case .completed(let result):
                return result
            case .nonZeroExit(let error):
                throw error
            case .failedToStart(let error):
                throw error
            case .terminatedByCancellation:
                throw CancellationError()
            }
        } onCancel: {
            runningProcess.requestTermination()
        }
    }

    private static func quoted(_ value: String) -> String {
        if value.contains(where: \.isWhitespace) {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return value
    }
}
