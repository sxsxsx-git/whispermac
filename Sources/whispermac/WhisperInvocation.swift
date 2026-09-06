import Foundation

enum WhisperInvocation {
    static func arguments(
        modelPath: String,
        wavPaths: [String],
        outputPrefixes: [String],
        formats: Set<OutputFormat>,
        sourceLanguage: String = WhisperLanguage.autoCode,
        translatesToEnglish: Bool = false
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
        if translatesToEnglish {
            arguments += ["--translate"]
        }
        arguments += formats.sorted { $0.rawValue < $1.rawValue }.map(\.whisperArgument)
        return arguments
    }
}
