import Foundation

// Resolves the HuggingFace base endpoint. Users behind the Great Firewall can
// point WhisperMac at a mirror either via the WHISPERMAC_HF_ENDPOINT environment
// variable or the "hfEndpoint" UserDefaults key; both asset and API URLs derive
// from it by replacing scheme + host while keeping the whisper.cpp paths.
enum HuggingFaceEndpoint {
    static let environmentVariableName = "WHISPERMAC_HF_ENDPOINT"
    static let storedValueDefaultsKey = "hfEndpoint"
    static let defaultBaseURL = URL(string: "https://huggingface.co")!
    private static let repositoryPath = "ggerganov/whisper.cpp"

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

    static func assetURL(fileName: String, baseURL: URL) -> URL {
        baseURL
            .appending(path: "\(repositoryPath)/resolve/main")
            .appending(path: fileName)
            .appending(queryItems: [URLQueryItem(name: "download", value: "true")])
    }

    static func treeAPIURL(baseURL: URL) -> URL {
        baseURL
            .appending(path: "api/models/\(repositoryPath)/tree/main")
            .appending(queryItems: [URLQueryItem(name: "recursive", value: "true")])
    }

    private static func sanitizedBaseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host(),
            !host.isEmpty
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url
    }
}
