import Testing
@testable import whispermac

@Test
func whisperStdoutTranscriptIsDropped() {
    let filtered = CommandLogFilter.filteredLine(
        for: .stdout,
        tool: .whisper,
        line: "[00:00:00.000 --> 00:00:02.000]  大家好"
    )

    #expect(filtered == nil)
}

@Test
func whisperProgressLineIsKept() {
    let filtered = CommandLogFilter.filteredLine(
        for: .stderr,
        tool: .whisper,
        line: "whisper_print_progress_callback: progress =  35%"
    )

    #expect(filtered == "whisper_print_progress_callback: progress =  35%")
}

@Test
func audioPreprocessorErrorLineIsKept() {
    let filtered = CommandLogFilter.filteredLine(
        for: .stderr,
        tool: .audioPreprocessor,
        line: "Error: cannot decode input file"
    )

    #expect(filtered == "Error: cannot decode input file")
}
