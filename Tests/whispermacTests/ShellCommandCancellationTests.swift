import Foundation
import Testing
@testable import whispermac

@Test
func cancelTerminatesLongRunningProcess() async throws {
    let startedAt = Date()
    let task = Task {
        try await ShellCommand.run(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 30 # whispermac-cancel-test"]
        )
    }

    try await Task.sleep(for: .milliseconds(200))
    task.cancel()

    var thrownError: (any Error)?
    do {
        _ = try await task.value
    } catch {
        thrownError = error
    }

    let elapsed = Date().timeIntervalSince(startedAt)
    #expect(thrownError is CancellationError)
    #expect(elapsed < 5, "expected the child process to be terminated, but the run took \(elapsed)s")
}

@Test
func normalCompletionStillSucceeds() async throws {
    let result = try await ShellCommand.run(executable: "/bin/echo", arguments: ["whispermac-shell-command-test"])

    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("whispermac-shell-command-test"))
}

@Test
func nonZeroExitStillThrowsNonZeroExit() async throws {
    var thrownError: (any Error)?
    do {
        _ = try await ShellCommand.run(executable: "/bin/cat", arguments: ["/nonexistent-whispermac-test-file"])
    } catch {
        thrownError = error
    }

    guard let shellError = thrownError as? ShellCommandError, case .nonZeroExit = shellError else {
        Issue.record("expected ShellCommandError.nonZeroExit, got \(String(describing: thrownError))")
        return
    }
}

@Test
func emitsOutputLinesInOrder() async throws {
    let collector = LineCollector()

    _ = try await ShellCommand.run(
        executable: "/bin/sh",
        arguments: ["-c", "for i in $(seq 1 500); do echo \"line-$i\"; done"],
        onOutput: { _, line in
            collector.append(line)
        }
    )

    let lines = collector.snapshot()
    let expected = (1...500).map { "line-\($0)" }
    #expect(lines == expected)
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
