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

    @MainActor
    static func chooseBinary() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// APFS is case-insensitive; compare standardized, lowercased paths.
private extension URL {
    var mediaDedupeKey: String {
        standardizedFileURL.path.lowercased()
    }
}
