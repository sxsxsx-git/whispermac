import Foundation

struct HuggingFaceTreeEntry: Decodable, Sendable {
    struct LFSInfo: Decodable, Sendable {
        let oid: String
    }

    let type: String?
    let path: String
    let lfs: LFSInfo?
}

// Decodes the model repository tree API response into a path -> SHA-256 map.
// Only LFS-tracked files carry a content digest (the LFS oid is the SHA-256 of
// the stored file); plain git files have none and are skipped.
enum HuggingFaceTree {
    static func sha256DigestMap(from data: Data) throws -> [String: String] {
        let entries = try JSONDecoder().decode([HuggingFaceTreeEntry].self, from: data)
        var digests: [String: String] = [:]
        for entry in entries {
            guard let oid = normalizedDigest(entry.lfs?.oid) else { continue }
            digests[entry.path] = oid
        }
        return digests
    }

    private static func normalizedDigest(_ rawOID: String?) -> String? {
        var value = rawOID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if value.hasPrefix("sha256:") {
            value.removeFirst("sha256:".count)
        }
        guard value.count == 64, value.allSatisfy(\.isHexDigit) else { return nil }
        return value
    }
}
