import Foundation

enum PathResolver {
    private static let preferredModelFileNames = [
        "ggml-large-v3-turbo.bin",
    ]
    /// Depth limit for recursive enumeration inside a directory the user
    /// explicitly pointed at. Automatic search directories are only ever
    /// checked non-recursively.
    private static let maxModelSearchDepth = 4

    private static let modelPathCache = ResolutionCache()

    /// Drops all cached resolution results. Call whenever the filesystem may
    /// have changed underneath an unchanged input: after the user manually
    /// picks a path, and after the runtime installer places new files.
    static func invalidateCaches() {
        modelPathCache.invalidateAll()
    }

    static var bundledRuntimeRoot: URL? {
        Bundle.main.resourceURL?.appending(path: "runtime")
    }

    static var applicationSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "WhisperMac", directoryHint: .isDirectory)
    }

    static var downloadedRuntimeRoot: URL {
        applicationSupportRoot.appending(path: "runtime", directoryHint: .isDirectory)
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
        let key = ResolutionCache.Key(
            input: value,
            whisperCLIPath: whisperCLIPath,
            searchRoots: searchRoots?.map(\.path)
        )
        if let cached = modelPathCache.cachedValue(for: key) {
            return cached
        }

        let resolved = resolveModelPathUncached(value, whisperCLIPath: whisperCLIPath, searchRoots: searchRoots)
        modelPathCache.store(resolved, for: key)
        return resolved
    }

    /// `resolveModelPath` minus the cache wrapper.
    ///
    /// Directories the user explicitly pointed at (the value's directory or
    /// its parent) keep recursive search; automatic search directories are
    /// only checked for exact/preferred file names directly inside them, so
    /// resolution never enumerates large directory trees. Only exact or
    /// preferred names match — arbitrary ggml-*.bin files are never guessed.
    private static func resolveModelPathUncached(_ value: String, whisperCLIPath: String?, searchRoots: [URL]?) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = expandingTilde(trimmed)
        let names = preferredModelNames(for: trimmed)

        var isDirectory: ObjCBool = false
        if !trimmed.isEmpty && FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                if let discovered = firstModelPath(
                    in: [URL(fileURLWithPath: expanded, isDirectory: true)],
                    preferredFileNames: names,
                    recursive: true
                ) {
                    return discovered
                }
            } else {
                return expanded
            }
        }

        let requestedDirectories = requestedSearchDirectories(for: trimmed)
        if let discovered = firstModelPath(in: requestedDirectories, preferredFileNames: names, recursive: true) {
            return discovered
        }

        let automaticDirectories = modelSearchDirectories(whisperCLIPath: whisperCLIPath, searchRoots: searchRoots)
        if let discovered = firstModelPath(in: automaticDirectories, preferredFileNames: names, recursive: false) {
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

    /// Directories searched automatically when the stored value does not point
    /// at a model: bundled runtime Models, the app's downloaded runtime Models,
    /// dev-layout roots, and directories derived from the whisper-cli
    /// location. Home directories (~/Models, ~/Downloads, ~/Documents,
    /// ~/Desktop) are deliberately absent: enumerating them is far too
    /// expensive for launch-time resolution and invites silently guessing at
    /// unrelated ggml-*.bin files. Users point at such models explicitly via
    /// the file picker instead.
    static func modelSearchDirectories(whisperCLIPath: String?, searchRoots: [URL]?) -> [URL] {
        let roots = candidateRoots(from: searchRoots)
        var directories = [URL]()

        if searchRoots == nil {
            if let bundledRuntimeRoot {
                directories.append(bundledRuntimeRoot.appending(path: "Models", directoryHint: .isDirectory))
            }
            directories.append(downloadedRuntimeRoot.appending(path: "Models", directoryHint: .isDirectory))
        }

        directories.append(contentsOf: roots.map { $0.appending(path: "Models", directoryHint: .isDirectory) })
        directories.append(contentsOf: roots.map { $0.appending(path: "models", directoryHint: .isDirectory) })
        directories.append(contentsOf: roots.map { $0.appending(path: ".build-tools/whisper.cpp/models", directoryHint: .isDirectory) })
        directories.append(contentsOf: roots.map { $0.appending(path: "Vendor/whisper.cpp/models", directoryHint: .isDirectory) })
        directories.append(contentsOf: derivedModelDirectories(from: whisperCLIPath))
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

    /// - Parameters:
    ///   - recursive: when true, directories are also enumerated (bounded by
    ///     `maxModelSearchDepth`) to find exact names nested deeper inside.
    ///     Reserved for directories the user explicitly designated; automatic
    ///     search directories only get the direct, non-recursive check.
    private static func firstModelPath(in directories: [URL], preferredFileNames: [String], recursive: Bool) -> String? {
        let exactNames = uniqueValues(preferredFileNames.filter { !$0.isEmpty })

        for directory in directories {
            for fileName in exactNames {
                let candidate = directory.appending(path: fileName).path
                if FileManager.default.fileExists(atPath: candidate) {
                    return candidate
                }
            }
        }

        guard recursive else { return nil }

        for directory in directories {
            if let discovered = firstMatchingModelPath(in: directory, exactNames: exactNames) {
                return discovered
            }
        }

        return nil
    }

    /// Recursive exact-name search inside a user-designated directory. Only
    /// exact/preferred file names match; there is deliberately no
    /// any-ggml-*.bin fallback pass.
    private static func firstMatchingModelPath(in directory: URL, exactNames: [String]) -> String? {
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

            if exactNames.contains(url.lastPathComponent) {
                return url.path
            }
        }

        return nil
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

/// Memo for synchronous path resolution, so repeated computed-property calls
/// (`canStart`, `accelerationSummary`, …) do not re-query the filesystem.
/// PathResolver exposes only synchronous static functions called from the main
/// actor, so an actor is not an option; every access goes through `lock`,
/// which makes the mutable storage safe (@unchecked Sendable).
/// Correctness over cleverness: bounded capacity with FIFO eviction, and a
/// single trivially-reliable `invalidateAll()`.
private final class ResolutionCache: @unchecked Sendable {
    struct Key: Hashable {
        let input: String
        let whisperCLIPath: String?
        let searchRoots: [String]?

        init(input: String, whisperCLIPath: String?, searchRoots: [String]?) {
            // Normalize so semantically identical calls share one entry.
            self.input = input.trimmingCharacters(in: .whitespacesAndNewlines)
            self.whisperCLIPath = whisperCLIPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.searchRoots = searchRoots?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    private static let capacity = 16

    private let lock = NSLock()
    private var storage: [Key: String] = [:]
    private var insertionOrder: [Key] = []

    func cachedValue(for key: Key) -> String? {
        lock.withLock { storage[key] }
    }

    func store(_ value: String, for key: Key) {
        lock.withLock {
            if storage[key] == nil {
                insertionOrder.append(key)
            }
            storage[key] = value
            if insertionOrder.count > Self.capacity {
                storage.removeValue(forKey: insertionOrder.removeFirst())
            }
        }
    }

    func invalidateAll() {
        lock.withLock {
            storage.removeAll()
            insertionOrder.removeAll()
        }
    }
}

struct ToolDefaults {
    let whisperCLIPath: String
    let modelPath: String
    let outputDirectoryPath: String
}
