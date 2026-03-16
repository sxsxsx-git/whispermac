import Foundation

enum PathResolver {
    static var bundledRuntimeRoot: URL? {
        Bundle.main.resourceURL?.appending(path: "runtime")
    }

    static var projectRoot: URL {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: current.appending(path: "Package.swift").path) ? current : bundleParent
    }

    static func guessDefaults() -> ToolDefaults {
        let roots = candidateRoots()

        let whisperCLI = firstExistingPath(
            bundledPaths(for: "bin/whisper-cli") +
            roots.map { $0.appending(path: ".build-tools/whisper.cpp/build/bin/whisper-cli").path } +
            roots.map { $0.appending(path: "Vendor/whisper.cpp/build/bin/whisper-cli").path } +
            [resolveExecutablePath("whisper-cli")]
        )

        let modelPath = firstExistingPath(
            bundledPaths(for: "Models/ggml-large-v3-turbo.bin") +
            roots.map { $0.appending(path: "Models/ggml-large-v3-turbo.bin").path } +
            roots.map { $0.appending(path: ".build-tools/whisper.cpp/models/ggml-large-v3-turbo.bin").path }
        )

        let defaultOutput = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Documents/WhisperMac Outputs")
            .path

        return ToolDefaults(
            whisperCLIPath: whisperCLI.isEmpty ? ".build-tools/whisper.cpp/build/bin/whisper-cli" : whisperCLI,
            modelPath: modelPath.isEmpty ? projectRoot.appending(path: "Models/ggml-large-v3-turbo.bin").path : modelPath,
            outputDirectoryPath: defaultOutput
        )
    }

    static func resolveExecutablePath(_ value: String) -> String {
        let expanded = expandingTilde(value)
        if expanded.contains("/") {
            return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : ""
        }

        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for path in paths {
            let candidate = URL(fileURLWithPath: path).appending(path: expanded).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return ""
    }

    static func expandingTilde(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private static func candidateRoots() -> [URL] {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        let bundleGrandparent = bundleParent.deletingLastPathComponent()
        return [current, projectRoot, bundleParent, bundleGrandparent]
    }

    private static func bundledPaths(for relativePath: String) -> [String] {
        guard let bundledRuntimeRoot else { return [] }
        return [bundledRuntimeRoot.appending(path: relativePath).path]
    }

    private static func firstExistingPath(_ values: [String]) -> String {
        values.first { !$0.isEmpty && FileManager.default.fileExists(atPath: expandingTilde($0)) } ?? ""
    }
}

struct ToolDefaults {
    let whisperCLIPath: String
    let modelPath: String
    let outputDirectoryPath: String
}
