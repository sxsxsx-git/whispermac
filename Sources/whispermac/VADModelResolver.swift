import Foundation

enum VADModelResolutionError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let path): L.tr("error.vad_model_missing", path)
        }
    }
}

enum VADModelResolver {
    static let fileName = "ggml-silero-v6.2.0.bin"
    static let minimumBytes: Int64 = 800_000
    static let maximumBytes: Int64 = 100_000_000
    static let requiredHeader = Data("lmgg\n\0\0\0silero-".utf8)

    static var downloadedModelURL: URL {
        PathResolver.downloadedRuntimeRoot
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    static func resolve(_ configuredPath: String, searchRoots: [URL]? = nil) -> String {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let candidate = URL(fileURLWithPath: PathResolver.expandingTilde(trimmed))
            return isValidModel(at: candidate) ? candidate.path : ""
        }

        let roots = searchRoots ?? [
            PathResolver.bundledRuntimeRoot?.appending(path: "Models", directoryHint: .isDirectory),
            PathResolver.downloadedRuntimeRoot.appending(path: "Models", directoryHint: .isDirectory),
        ].compactMap { $0 }
        for root in roots {
            let candidate = root.appending(path: fileName)
            if isValidModel(at: candidate) { return candidate.path }
        }
        return ""
    }

    static func isValidModel(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value
        else { return false }
        guard size >= minimumBytes, size <= maximumBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return false }
        return data.prefix(requiredHeader.count).elementsEqual(requiredHeader)
    }
}
