import Foundation

enum CommandLogFilter {
    static func filteredLine(for stream: ShellOutputStream, tool: CommandLogTool, line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch tool {
        case .audioPreprocessor:
            return filteredAudioPreprocessorLine(stream: stream, line: trimmed)
        case .whisper:
            return filteredWhisperLine(stream: stream, line: trimmed)
        }
    }

    private static func filteredAudioPreprocessorLine(stream: ShellOutputStream, line: String) -> String? {
        if stream == .stdout {
            return nil
        }

        return line
    }

    private static func filteredWhisperLine(stream: ShellOutputStream, line: String) -> String? {
        if stream == .stdout {
            return nil
        }

        let usefulPrefixes = [
            "whisper_init_",
            "whisper_model_load:",
            "whisper_backend_init",
            "whisper_backend_init_gpu:",
            "whisper_print_progress_callback:",
            "ggml_metal_init:",
            "ggml_metal_device_init: GPU name:",
            "ggml_metal_device_init: found device:",
            "ggml_metal_device_init: use ",
        ]

        let usefulFragments = [
            "Core ML",
            "failed",
            "error",
            "warning",
            "progress =",
            "model size",
            "total size",
            "kv self size",
            "kv cross size",
            "kv pad  size",
            "use gpu",
            "gpu_device",
            "flash attn",
            "devices    =",
            "backends   =",
        ]

        if usefulPrefixes.contains(where: { line.hasPrefix($0) }) || usefulFragments.contains(where: { line.contains($0) }) {
            return line
        }

        return nil
    }
}

enum CommandLogTool: Sendable {
    case audioPreprocessor
    case whisper
}
