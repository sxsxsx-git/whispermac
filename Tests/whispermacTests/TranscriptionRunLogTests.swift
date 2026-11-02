import Foundation
import Testing
@testable import whispermac

@Test
func diagnosticLogPreservesUnfilteredOutputAndFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = try TranscriptionRunLog(directory: directory)
    do {
        _ = try await TranscriptionRunLog.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'repeated phrase\\n'; printf 'decoder fallback detail\\n' >&2; exit 7"],
            log: log,
            onOutput: { _, _ in }
        )
        Issue.record("Expected nonzero exit")
    } catch ShellCommandError.nonZeroExit(_, let code, _) {
        #expect(code == 7)
    }
    let contents = try String(contentsOf: log.url, encoding: .utf8)
    #expect(contents.contains("command: ["))
    #expect(contents.contains("[stdout] repeated phrase"))
    #expect(contents.contains("[stderr] decoder fallback detail"))
    #expect(contents.contains("error:"))
}
