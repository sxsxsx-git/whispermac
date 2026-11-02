import Foundation

enum WhisperInvocation {
    static func arguments(
        modelPath: String,
        wavPaths: [String],
        outputPrefixes: [String],
        formats: Set<OutputFormat>,
        sourceLanguage: String = WhisperLanguage.autoCode,
        translatesToEnglish: Bool = false,
        usesTextContext: Bool = false
    ) -> [String] {
        precondition(
            wavPaths.count == outputPrefixes.count,
            "each wav needs a matching -of prefix: cli.cpp pairs the i-th -of with the i-th input"
        )
        var arguments: [String] = [
            "-m", PathResolver.expandingTilde(modelPath),
        ]
        arguments += wavPaths.flatMap { ["-f", $0] }
        arguments += outputPrefixes.flatMap { ["-of", $0] }
        arguments += ["-l", sourceLanguage, "-pp"]
        // By default, do not feed decoded text back into subsequent audio windows. A bad
        // phrase can otherwise reinforce itself for the rest of a long file.
        // no_context in whisper.cpp only clears history at the start of a call;
        // a zero text-context budget also disables reuse within that call.
        if !usesTextContext {
            arguments += ["-mc", "0"]
        }
        if translatesToEnglish {
            arguments += ["--translate"]
        }
        arguments += formats.sorted { $0.rawValue < $1.rawValue }.map(\.whisperArgument)
        return arguments
    }
}
