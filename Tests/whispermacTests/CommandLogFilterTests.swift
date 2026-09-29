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

@Test
func vadSummaryAndFailureLinesAreKept() {
    #expect(CommandLogFilter.filteredLine(
        for: .stderr,
        tool: .whisper,
        line: "whisper_vad_segments_from_probs: Final speech segments after filtering: 8"
    ) != nil)
    #expect(CommandLogFilter.filteredLine(
        for: .stderr,
        tool: .whisper,
        line: "whisper_vad_init_with_params: model version: 6.2.0"
    ) != nil)
    #expect(CommandLogFilter.filteredLine(
        for: .stderr,
        tool: .whisper,
        line: "whisper_vad_process: failed to decode model"
    ) != nil)
}

@Test
func repetitiveVADWindowLinesAreFiltered() {
    #expect(CommandLogFilter.filteredLine(
        for: .stderr,
        tool: .whisper,
        line: "whisper_vad_segments_from_probs: VAD segment 281: start = 82.0, end = 83.0"
    ) == nil)
}

@Test
func gpuInitializationFailureIsNeverHiddenWhenVADIsEnabled() {
    let backendLine = "whisper_backend_init_gpu: no GPU found"
    #expect(CommandLogFilter.filteredLine(for: .stderr, tool: .whisper, line: backendLine) == backendLine)
}
