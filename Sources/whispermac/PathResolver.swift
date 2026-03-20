import Foundation

enum PathResolver {
    private static let preferredModelFileNames = [
        "ggml-large-v3-turbo.bin",
    ]
    private static let maxModelSearchDepth = 4

    static var bundledRuntimeRoot: URL? {
        Bundle.main.resourceURL?.appending(path: "runtime")
    }

    static var projectRoot: URL {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: current.appending(path: "Package.swift").path) ? current : bundleParent
    }

    static func guessDefaults() -> ToolDefaults {
        let whisperCLI = resolveWhisperCLIPath("")
        let modelPath = resolveModelPath("", whisperCLIPath: whisperCLI)

        let defaultOutput = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Documents/WhisperMac Outputs")
            .path

        return ToolDefaults(
            whisperCLIPath: whisperCLI.isEmpty ? ".build-tools/whisper.cpp/build/bin/whisper-cli" : whisperCLI,
            modelPath: modelPath.isEmpty ? projectRoot.appending(path: "Models/ggml-large-v3-turbo.bin").path : modelPath,
            outputDirectoryPath: defaultOutput
        )
    }

    static func resolveWhisperCLIPath(_ value: String, searchRoots: [URL]? = nil) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicit = resolveExecutablePath(trimmed)
        if !explicit.isEmpty {
            return explicit
        }

        let roots = candidateRoots(from: searchRoots)
        let candidates = bundledPaths(for: "bin/whisper-cli") +
            roots.map { $0.appending(path: ".build-tools/whisper.cpp/build/bin/whisper-cli").path } +
            roots.map { $0.appending(path: "Vendor/whisper.cpp/build/bin/whisper-cli").path } +
            roots.map { $0.appending(path: "build/bin/whisper-cli").path } +
            [resolveExecutablePath("whisper-cli")]

        return firstExecutablePath(candidates)
    }

    static func resolveModelPath(_ value: String, whisperCLIPath: String? = nil, searchRoots: [URL]? = nil) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = expandingTilde(trimmed)

        var isDirectory: ObjCBool = false
        if !trimmed.isEmpty && FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                if let discovered = firstModelPath(
                    in: [URL(fileURLWithPath: expanded, isDirectory: true)],
                    preferredFileNames: preferredModelNames(for: trimmed)
                ) {
                    return discovered
                }
            } else {
                return expanded
            }
        }

        let searchDirectories = uniqueDirectories(
            requestedSearchDirectories(for: trimmed) +
            modelSearchDirectories(whisperCLIPath: whisperCLIPath, searchRoots: searchRoots)
        )

        if let discovered = firstModelPath(
            in: searchDirectories,
            preferredFileNames: preferredModelNames(for: trimmed)
        ) {
            return discovered
        }

        return ""
    }

    static func resolveExecutablePath(_ value: String) -> String {
        let expanded = expandingTilde(value)
        if expanded.contains("/") {
            return isExecutableFilePath(expanded) ? expanded : ""
        }

        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for path in paths {
            let candidate = URL(fileURLWithPath: path).appending(path: expanded).path
            if isExecutableFilePath(candidate) {
                return candidate
            }
        }

        return ""
    }

    static func expandingTilde(_ value: String) -> String {
        NSString(string: value).expandingTildeInPath
    }

    private static func candidateRoots(from explicitRoots: [URL]? = nil) -> [URL] {
        if let explicitRoots {
            return uniqueDirectories(explicitRoots)
        }

        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        let bundleGrandparent = bundleParent.deletingLastPathComponent()
        return uniqueDirectories([current, projectRoot, bundleParent, bundleGrandparent])
    }

    private static func bundledPaths(for relativePath: String) -> [String] {
        guard let bundledRuntimeRoot else { return [] }
        return [bundledRuntimeRoot.appending(path: relativePath).path]
    }

    private static func requestedSearchDirectories(for value: String) -> [URL] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let expanded = expandingTilde(trimmed)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return [URL(fileURLWithPath: expanded, isDirectory: true)]
        }

        let parent = URL(fileURLWithPath: expanded).deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: parent.path) ? [parent] : []
    }

    private static func modelSearchDirectories(whisperCLIPath: String?, searchRoots: [URL]?) -> [URL] {
        let roots = candidateRoots(from: searchRoots)
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories = [URL]()
        if let bundledRuntimeRoot {
            directories.append(bundledRuntimeRoot.appending(path: "Models", directoryHint: .isDirectory))
        }
        directories.append(contentsOf: roots.map { $0.appending(path: "Models", directoryHint: .isDirectory) })
        directories.append(contentsOf: roots.map { $0.appending(path: "models", directoryHint: .isDirectory) })
        directories.append(contentsOf: roots.map { $0.appending(path: ".build-tools/whisper.cpp/models", directoryHint: .isDirectory) })
        directories.append(contentsOf: roots.map { $0.appending(path: "Vendor/whisper.cpp/models", directoryHint: .isDirectory) })
        directories.append(contentsOf: derivedModelDirectories(from: whisperCLIPath))
        directories.append(contentsOf: [
            home.appending(path: "Models", directoryHint: .isDirectory),
            home.appending(path: "Downloads", directoryHint: .isDirectory),
            home.appending(path: "Documents", directoryHint: .isDirectory),
            home.appending(path: "Desktop", directoryHint: .isDirectory),
        ])
        return uniqueDirectories(directories)
    }

    private static func derivedModelDirectories(from whisperCLIPath: String?) -> [URL] {
        guard let whisperCLIPath else { return [] }

        let resolvedWhisperCLIPath = resolveWhisperCLIPath(whisperCLIPath)
        guard !resolvedWhisperCLIPath.isEmpty else { return [] }

        let executableDirectory = URL(fileURLWithPath: resolvedWhisperCLIPath).deletingLastPathComponent()
        let buildDirectory = executableDirectory.deletingLastPathComponent()
        let whisperRoot = buildDirectory.deletingLastPathComponent()

        return [
            executableDirectory.appending(path: "models", directoryHint: .isDirectory),
            buildDirectory.appending(path: "models", directoryHint: .isDirectory),
            whisperRoot.appending(path: "models", directoryHint: .isDirectory),
            whisperRoot.appending(path: "Models", directoryHint: .isDirectory),
        ]
    }

    private static func preferredModelNames(for value: String) -> [String] {
        let requestedName = requestedModelFileName(for: value)
        var names = [String]()
        if let requestedName {
            names.append(requestedName)
        }
        names.append(contentsOf: preferredModelFileNames)
        return uniqueValues(names)
    }

    private static func requestedModelFileName(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !name.isEmpty, name.lowercased().hasSuffix(".bin") else { return nil }
        return name
    }

    private static func firstModelPath(in directories: [URL], preferredFileNames: [String]) -> String? {
        let exactNames = uniqueValues(preferredFileNames.filter { !$0.isEmpty })

        for directory in directories {
            for fileName in exactNames {
                let candidate = directory.appending(path: fileName).path
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }

        for directory in directories {
            if let discovered = firstMatchingModelPath(in: directory, exactNames: exactNames, allowFallbackMatches: false) {
                return discovered
            }
        }

        for directory in directories {
            if let discovered = firstMatchingModelPath(in: directory, exactNames: [], allowFallbackMatches: true) {
                return discovered
            }
        }

        return nil
    }

    private static func firstMatchingModelPath(in directory: URL, exactNames: [String], allowFallbackMatches: Bool) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let rootDepth = directory.pathComponents.count
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - rootDepth
            if depth > maxModelSearchDepth {
                enumerator.skipDescendants()
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                continue
            }

            let fileName = url.lastPathComponent
            if exactNames.contains(fileName) {
                return url.path
            }
            if allowFallbackMatches && isCandidateModelFileName(fileName) {
                return url.path
            }
        }

        return nil
    }

    private static func isCandidateModelFileName(_ value: String) -> Bool {
        let lowercase = value.lowercased()
        return lowercase.hasPrefix("ggml-") && lowercase.hasSuffix(".bin")
    }

    private static func firstExecutablePath(_ values: [String]) -> String {
        uniqueValues(values.map(expandingTilde))
            .first { !$0.isEmpty && isExecutableFilePath($0) } ?? ""
    }

    private static func isExecutableFilePath(_ value: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: value, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: value)
    }

    private static func uniqueDirectories(_ values: [URL]) -> [URL] {
        var seen = Set<String>()
        return values.filter { url in
            let path = url.standardizedFileURL.path
            return seen.insert(path).inserted
        }
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            !value.isEmpty && seen.insert(value).inserted
        }
    }
}

struct ToolDefaults {
    let whisperCLIPath: String
    let modelPath: String
    let outputDirectoryPath: String
}
