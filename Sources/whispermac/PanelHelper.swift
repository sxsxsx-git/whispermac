import AppKit
import UniformTypeIdentifiers

enum PanelHelper {
    static let supportedMediaTypes: [UTType] = [
        .mpeg4Movie,
        UTType(filenameExtension: "m4a"),
        UTType(filenameExtension: "mp3"),
        UTType(filenameExtension: "wav"),
        UTType(filenameExtension: "aac"),
        UTType(filenameExtension: "mov"),
        UTType(filenameExtension: "m4v"),
        UTType(filenameExtension: "flac"),
    ].compactMap { $0 }

    static func supportsFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return supportedMediaTypes.contains(where: { type.conforms(to: $0) || $0.conforms(to: type) })
    }

    static func mediaFileAdditions(from candidates: [URL], existing: [URL]) -> [URL] {
        var seen = Set(existing.map(\.mediaDedupeKey))
        var additions: [URL] = []
        for candidate in candidates {
            guard supportsFile(candidate), seen.insert(candidate.mediaDedupeKey).inserted else { continue }
            additions.append(candidate)
        }
        return additions
    }

    static func mediaDedupeKey(for url: URL, caseSensitive: Bool) -> String {
        let path = url.standardizedFileURL.path
        return caseSensitive ? path : path.lowercased()
    }

    static func expandedMediaURLs(from candidates: [URL]) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            enumerateMediaFiles(from: candidates)
        }.value
    }

    /// Runs entirely off the main actor. Top-level file order is preserved;
    /// files found inside each directory are sorted for repeatable queue order.
    nonisolated static func enumerateMediaFiles(from candidates: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .isPackageKey,
        ]

        func appendIfNew(_ url: URL) {
            guard seen.insert(url.mediaDedupeKey).inserted else { return }
            result.append(url)
        }

        for candidate in candidates {
            guard let values = try? candidate.resourceValues(forKeys: keys),
                  values.isHidden != true, values.isSymbolicLink != true
            else { continue }

            if values.isRegularFile == true {
                if supportsFile(candidate) { appendIfNew(candidate) }
                continue
            }
            guard values.isDirectory == true, values.isPackage != true else { continue }

            guard let enumerator = fileManager.enumerator(
                at: candidate,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            var directoryFiles: [URL] = []
            while let url = enumerator.nextObject() as? URL {
                guard let childValues = try? url.resourceValues(forKeys: keys) else { continue }
                if childValues.isSymbolicLink == true || childValues.isPackage == true {
                    if childValues.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                if childValues.isRegularFile == true, supportsFile(url) {
                    directoryFiles.append(url)
                }
            }
            directoryFiles.sort { $0.standardizedFileURL.path.localizedStandardCompare($1.standardizedFileURL.path) == .orderedAscending }
            for url in directoryFiles { appendIfNew(url) }
        }
        return result
    }

    @MainActor
    static func chooseBinary() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// Respect the volume's filename case-sensitivity when building normalized
// deduplication keys.
private extension URL {
    var mediaDedupeKey: String {
        let supportsCaseSensitiveNames = try? resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames
        return PanelHelper.mediaDedupeKey(for: self, caseSensitive: supportsCaseSensitiveNames ?? false)
    }
}
