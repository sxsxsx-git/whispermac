import Foundation

enum OutputPaths {
    static func temporaryWAVURL(for inputURL: URL) -> URL {
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let name = "\(stem)-\(UUID().uuidString).wav"
        return FileManager.default.temporaryDirectory.appending(path: name)
    }

    static func outputPrefixURL(for inputURL: URL, outputDirectory: URL) -> URL {
        outputDirectory.appending(path: inputURL.deletingPathExtension().lastPathComponent)
    }

    static func uniqueOutputPrefix(
        for inputURL: URL,
        outputDirectory: URL,
        formats: Set<OutputFormat>,
        takenPrefixes: Set<String>
    ) -> URL {
        let stem = inputURL.deletingPathExtension().lastPathComponent
        var candidate = outputDirectory.appending(path: stem)
        var bump = 0
        while collides(candidate, formats: formats, takenPrefixes: takenPrefixes) {
            bump += 1
            candidate = outputDirectory.appending(path: "\(stem)-\(bump)")
        }
        return candidate
    }

    static func outputFiles(prefix: URL, formats: Set<OutputFormat>) -> [URL] {
        formats
            .sorted { $0.rawValue < $1.rawValue }
            .map { prefix.appendingPathExtension($0.rawValue) }
    }

    static func outputFiles(for inputURL: URL, outputDirectory: URL, formats: Set<OutputFormat>) -> [URL] {
        outputFiles(prefix: outputPrefixURL(for: inputURL, outputDirectory: outputDirectory), formats: formats)
    }

    private static func collides(_ prefix: URL, formats: Set<OutputFormat>, takenPrefixes: Set<String>) -> Bool {
        if takenPrefixes.contains(where: { $0.caseInsensitiveCompare(prefix.path) == .orderedSame }) {
            return true
        }
        return formats.contains { format in
            FileManager.default.fileExists(atPath: prefix.appendingPathExtension(format.rawValue).path)
        }
    }

    static func coreMLModelURL(for modelURL: URL) -> URL {
        let stem = modelURL.deletingPathExtension().lastPathComponent
        return modelURL.deletingLastPathComponent().appending(path: "\(stem)-encoder.mlmodelc")
    }
}
