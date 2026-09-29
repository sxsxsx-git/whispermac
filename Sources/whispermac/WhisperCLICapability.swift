import Foundation

enum WhisperCLICapability: Equatable, Sendable {
    case unchecked
    case checking
    case supported
    case unsupported
}

final class WhisperCLICapabilityChecker: @unchecked Sendable {
    static let shared = WhisperCLICapabilityChecker()

    private struct CacheKey: Hashable {
        let path: String
        let modificationDate: Date?
    }

    private let lock = NSLock()
    private var cache: [CacheKey: Bool] = [:]

    func supportsVAD(at path: String) async -> Bool {
        let resolvedPath = PathResolver.expandingTilde(path)
        guard FileManager.default.isExecutableFile(atPath: resolvedPath),
              let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath)
        else { return false }

        let key = CacheKey(path: resolvedPath, modificationDate: attributes[.modificationDate] as? Date)
        let cached = lock.withLock { cache[key] }
        if let cached { return cached }

        let supported: Bool
        do {
            let result = try await ShellCommand.run(executable: resolvedPath, arguments: ["--help"])
            supported = Self.helpOutputSupportsVAD(result.combinedOutput)
        } catch {
            supported = false
        }

        lock.withLock {
            cache = cache.filter { $0.key.path != resolvedPath }
            cache[key] = supported
        }
        return supported
    }

    static func helpOutputSupportsVAD(_ help: String) -> Bool {
        help.range(of: #"--vad(?:\s|,|$)"#, options: .regularExpression) != nil &&
            help.contains("--vad-model")
    }
}
