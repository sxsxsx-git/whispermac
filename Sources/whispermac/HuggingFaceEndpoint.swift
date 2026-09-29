import Foundation

// Resolves the HuggingFace base endpoint. Users behind the Great Firewall can
// point WhisperMac at a mirror either via the WHISPERMAC_HF_ENDPOINT environment
// variable or the "hfEndpoint" UserDefaults key; both asset and API URLs derive
// from it by replacing scheme + host while keeping the whisper.cpp paths.
enum HuggingFaceEndpoint {
    static let environmentVariableName = "WHISPERMAC_HF_ENDPOINT"
    static let storedValueDefaultsKey = "hfEndpoint"
    static let defaultBaseURL = URL(string: "https://huggingface.co")!
    static let hfMirrorBaseURL = URL(string: "https://hf-mirror.com")!
    static let whisperRepository = "ggerganov/whisper.cpp"

    static func resolved() -> URL {
        resolved(
            environment: ProcessInfo.processInfo.environment,
            storedValue: UserDefaults.standard.string(forKey: storedValueDefaultsKey)
        )
    }

    static func resolved(environment: [String: String], storedValue: String?) -> URL {
        let candidates = [environment[environmentVariableName], storedValue].compactMap { $0 }
        for candidate in candidates {
            if let url = sanitizedBaseURL(from: candidate) {
                return url
            }
        }
        return defaultBaseURL
    }

    /// Resolves the user-facing source selection. A configured environment
    /// override always wins; invalid values remain `nil` so callers can block
    /// downloads instead of silently changing the selected host.
    static func resolved(
        source: HuggingFaceDownloadSource,
        customValue: String?,
        environment: [String: String]
    ) -> URL? {
        if let override = environment[environmentVariableName] {
            return sanitizedBaseURL(from: override)
        }
        switch source {
        case .official: return defaultBaseURL
        case .hfMirror: return hfMirrorBaseURL
        case .custom: return customValue.flatMap(sanitizedBaseURL(from:))
        }
    }

    static func sanitizedBaseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host(),
            !host.isEmpty
        else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url
    }

    static func assetURL(fileName: String, baseURL: URL, repository: String = whisperRepository) -> URL {
        baseURL
            .appending(path: "\(repository)/resolve/main")
            .appending(path: fileName)
            .appending(queryItems: [URLQueryItem(name: "download", value: "true")])
    }

    static func treeAPIURL(baseURL: URL, repository: String = whisperRepository) -> URL {
        baseURL
            .appending(path: "api/models/\(repository)/tree/main")
            .appending(queryItems: [URLQueryItem(name: "recursive", value: "true")])
    }

}
