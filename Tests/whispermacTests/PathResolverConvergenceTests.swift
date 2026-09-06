import Foundation
import Testing
@testable import whispermac

/// Serialized because these tests share PathResolver's process-wide resolution
/// cache and the eviction test deliberately saturates it.
@Suite(.serialized)
struct PathResolverConvergenceTests {
    @Test
    func modelSearchDirectoriesSkipHomeDirectorySprawl() {
        let directories = PathResolver.modelSearchDirectories(whisperCLIPath: nil, searchRoots: nil)
        let paths = directories.map(\.path)
        let home = FileManager.default.homeDirectoryForCurrentUser

        for name in ["Models", "Downloads", "Documents", "Desktop"] {
            let sprawlRoot = home.appending(path: name, directoryHint: .isDirectory).path
            #expect(!paths.contains(sprawlRoot), "search domain must not include \(sprawlRoot)")
        }

        #expect(paths.contains(PathResolver.downloadedRuntimeRoot.appending(path: "Models").path))
        if let bundledRuntimeRoot = PathResolver.bundledRuntimeRoot {
            #expect(paths.contains(bundledRuntimeRoot.appending(path: "Models").path))
        }
        #expect(paths.contains(PathResolver.projectRoot.appending(path: "Models").path))
        #expect(paths.contains(PathResolver.projectRoot.appending(path: "models").path))
    }

    @Test
    func resolveModelPathDoesNotGuessUnfamiliarModelNames() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let decoyDirectory = root.appending(path: "Models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: decoyDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: decoyDirectory.appending(path: "ggml-tiny-test.bin").path, contents: Data())

        let resolved = PathResolver.resolveModelPath("", searchRoots: [root])

        #expect(resolved.isEmpty)
    }

    @Test
    func resolveModelPathPicksPreferredNameInSearchDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let modelURL = root.appending(path: "Models/ggml-large-v3-turbo.bin")
        try FileManager.default.createDirectory(at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelURL.path, contents: Data())

        let resolved = PathResolver.resolveModelPath("", searchRoots: [root])

        #expect(resolved == modelURL.path)
    }

    @Test
    func resolveModelPathRecursesInsideExplicitDirectoryForPreferredName() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let nestedDirectory = root.appending(path: "Downloads/whisper-models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        let modelURL = nestedDirectory.appending(path: "ggml-large-v3-turbo.bin")
        FileManager.default.createFile(atPath: modelURL.path, contents: Data())

        let resolved = PathResolver.resolveModelPath(root.appending(path: "Downloads").path)

        #expect(URL(fileURLWithPath: resolved).standardizedFileURL.path == modelURL.standardizedFileURL.path)
    }

    @Test
    func resolveModelPathServesCachedResultUntilInvalidated() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let modelURL = root.appending(path: "Models/ggml-large-v3-turbo.bin")
        try FileManager.default.createDirectory(at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelURL.path, contents: Data())

        let first = PathResolver.resolveModelPath("", searchRoots: [root])
        #expect(first == modelURL.path)

        try FileManager.default.removeItem(at: modelURL)
        let cached = PathResolver.resolveModelPath("", searchRoots: [root])
        #expect(cached == first)

        PathResolver.invalidateCaches()
        let refreshed = PathResolver.resolveModelPath("", searchRoots: [root])
        #expect(refreshed.isEmpty)
    }

    @Test
    func resolveModelPathCacheEvictsOldestEntriesBeyondCapacity() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let modelURL = root.appending(path: "Models/ggml-large-v3-turbo.bin")
        try FileManager.default.createDirectory(at: modelURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: modelURL.path, contents: Data())

        #expect(PathResolver.resolveModelPath("", searchRoots: [root]) == modelURL.path)

        // Push 16 further distinct keys so the first entry falls out of the cache.
        for index in 0..<16 {
            let otherRoot = root.appending(path: "saturate-\(index)", directoryHint: .isDirectory)
            #expect(PathResolver.resolveModelPath("", searchRoots: [otherRoot]).isEmpty)
        }

        try FileManager.default.removeItem(at: modelURL)
        let resolved = PathResolver.resolveModelPath("", searchRoots: [root])
        #expect(resolved.isEmpty)
    }
}
