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

    static func outputFiles(for inputURL: URL, outputDirectory: URL, formats: Set<OutputFormat>) -> [URL] {
        let prefix = outputPrefixURL(for: inputURL, outputDirectory: outputDirectory)
        return formats
            .sorted { $0.rawValue < $1.rawValue }
            .map { prefix.appendingPathExtension($0.rawValue) }
    }

    static func coreMLModelURL(for modelURL: URL) -> URL {
        let stem = modelURL.deletingPathExtension().lastPathComponent
        return modelURL.deletingLastPathComponent().appending(path: "\(stem)-encoder.mlmodelc")
    }
}
