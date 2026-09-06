import CryptoKit
import Foundation
import Testing
@testable import whispermac

// Fixture mirrors the real response of
// https://huggingface.co/api/models/ggerganov/whisper.cpp/tree/main?recursive=true
private let treeJSON = """
[
  {"type":"file","oid":"bb0749e3c17cdf1d040a7e95fbf45610a212ec0a","size":3196,"path":"README.md"},
  {"type":"file","oid":"819841c70bdf4488c4ff778f8becdcb37df43969","size":1624555275,"lfs":{"oid":"1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69","size":1624555275,"pointerSize":135},"xetHash":"5a4b65b05933d70ce9d5aa6265eb128fa5eba38f6fee40836fdedc4d2fde42ad","path":"ggml-large-v3-turbo.bin"},
  {"type":"file","oid":"9a92b77ae93111849ccabadc8bf4441233ad58a8","size":1173393014,"lfs":{"oid":"84bedfe895bd7b5de6e8e89a0803dfc5addf8c0c5bc4c937451716bf7cf7988a","size":1173393014,"pointerSize":135},"xetHash":"386e2a4079bcc19c8284cc0294fde49e32981ba07157ee82dd3b3cbb42177100","path":"ggml-large-v3-turbo-encoder.mlmodelc.zip"}
]
"""

struct RuntimeDownloadTests {
    private static let modelDigest = "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"

    // MARK: - Endpoint derivation

    @Test
    func endpointResolvesToHuggingFaceByDefault() {
        let url = HuggingFaceEndpoint.resolved(environment: [:], storedValue: nil)
        #expect(url == URL(string: "https://huggingface.co"))
    }

    @Test
    func endpointNormalizesCustomHostWithOrWithoutTrailingSlash() {
        let withoutSlash = HuggingFaceEndpoint.resolved(environment: [:], storedValue: "https://hf-mirror.com")
        let withSlash = HuggingFaceEndpoint.resolved(environment: [:], storedValue: "https://hf-mirror.com/")
        #expect(withoutSlash.absoluteString == "https://hf-mirror.com")
        #expect(withSlash == withoutSlash)
    }

    @Test
    func endpointPrefersEnvironmentOverrideOverStoredValue() {
        let url = HuggingFaceEndpoint.resolved(
            environment: [HuggingFaceEndpoint.environmentVariableName: "https://mirror.internal:8443"],
            storedValue: "https://hf-mirror.com"
        )
        #expect(url.absoluteString == "https://mirror.internal:8443")
    }

    @Test
    func endpointFallsBackToDefaultWhenOverridesAreInvalid() {
        #expect(HuggingFaceEndpoint.resolved(environment: [:], storedValue: "not a url") == HuggingFaceEndpoint.defaultBaseURL)
        #expect(HuggingFaceEndpoint.resolved(environment: [:], storedValue: "   ") == HuggingFaceEndpoint.defaultBaseURL)
        #expect(
            HuggingFaceEndpoint.resolved(
                environment: [HuggingFaceEndpoint.environmentVariableName: "ftp://example.com"],
                storedValue: nil
            ) == HuggingFaceEndpoint.defaultBaseURL
        )
    }

    @Test
    func endpointDerivesAssetAndAPITargetsFromBase() {
        let base = URL(string: "https://hf-mirror.com")!
        let model = HuggingFaceEndpoint.assetURL(fileName: "ggml-large-v3-turbo.bin", baseURL: base)
        #expect(model.absoluteString == "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")

        let api = HuggingFaceEndpoint.treeAPIURL(baseURL: base)
        #expect(api.absoluteString == "https://hf-mirror.com/api/models/ggerganov/whisper.cpp/tree/main?recursive=true")
    }

    // MARK: - Digest JSON decoding

    @Test
    func digestMapDecodesLFSOidsFromTreeJSON() throws {
        let map = try HuggingFaceTree.sha256DigestMap(from: Data(treeJSON.utf8))
        #expect(map["ggml-large-v3-turbo.bin"] == Self.modelDigest)
        #expect(map["ggml-large-v3-turbo-encoder.mlmodelc.zip"] == "84bedfe895bd7b5de6e8e89a0803dfc5addf8c0c5bc4c937451716bf7cf7988a")
        #expect(map["README.md"] == nil)
        #expect(map.count == 2)
    }

    @Test
    func digestMapToleratesWhitespaceMissingLFSOddCasingAndPrefixes() throws {
        let json = """

        [
            {
                "type": "directory",
                "oid": "abc123",
                "path": "folder",
                "size": 0
            },
            {
                "type": "file",
                "oid": "def456",
                "path": "plain.txt"
            },
            {
                "type": "file",
                "oid": "aaa",
                "lfs": {"oid": "1FC70F774D38EB169993AC391EEA357EF47C88757EF72EE5943879B7E8E2BC69", "size": 1, "pointerSize": 9},
                "path": "upper.bin"
            },
            {
                "type": "file",
                "oid": "bbb",
                "lfs": {"oid": "sha256:84bedfe895bd7b5de6e8e89a0803dfc5addf8c0c5bc4c937451716bf7cf7988a", "size": 1, "pointerSize": 9},
                "path": "prefixed.bin"
            },
            {
                "type": "file",
                "oid": "ccc",
                "lfs": {"oid": "not-a-digest", "size": 1, "pointerSize": 9},
                "path": "garbage.bin"
            }
        ]

        """
        let map = try HuggingFaceTree.sha256DigestMap(from: Data(json.utf8))
        #expect(map == [
            "upper.bin": Self.modelDigest,
            "prefixed.bin": "84bedfe895bd7b5de6e8e89a0803dfc5addf8c0c5bc4c937451716bf7cf7988a",
        ])
    }

    @Test
    func digestMapThrowsOnMalformedJSON() {
        #expect(throws: (any Error).self) {
            try HuggingFaceTree.sha256DigestMap(from: Data("<html>rate limited</html>".utf8))
        }
    }

    // MARK: - SHA-256 file streaming

    @Test
    func sha256DigestMatchesKnownAnswerAcrossTinyChunks() throws {
        let url = try Self.writeTemporaryFile(named: "hello.bin", contents: Data("hello world".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let digest = try FileHasher.sha256HexDigest(ofFileAt: url, chunkSize: 4)
        #expect(digest == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    @Test
    func sha256DigestStreamsLargeFileInChunks() throws {
        let full = Data((0..<(5 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 * 31) })
        let url = try Self.writeTemporaryFile(named: "large.bin", contents: full)
        defer { try? FileManager.default.removeItem(at: url) }

        let streamed = try FileHasher.sha256HexDigest(ofFileAt: url, chunkSize: 64 * 1024)
        let inMemory = SHA256.hash(data: full).map { String(format: "%02x", $0) }.joined()
        #expect(streamed == inMemory)
    }

    // MARK: - Download validation (size gate + magic + digest)

    @Test
    func validationRejectsFileBelowMinimumSize() throws {
        let url = try Self.writeModelLikeFile(named: "tiny.bin", byteCount: 1024)
        defer { try? FileManager.default.removeItem(at: url) }

        let outcome = try DownloadValidator.validate(
            fileAt: url,
            expectation: DownloadExpectation(minimumBytes: 1_000_000, expectedDigest: nil, requiredMagicBytes: DownloadExpectation.ggmlMagic)
        )
        #expect(outcome == .rejected(.belowMinimumSize(minimumBytes: 1_000_000, actualBytes: 1024)))
    }

    @Test
    func validationAcceptsSizeWhenDigestUnavailable() throws {
        let url = try Self.writeModelLikeFile(named: "ok.bin", byteCount: 1_000_001)
        defer { try? FileManager.default.removeItem(at: url) }

        let outcome = try DownloadValidator.validate(
            fileAt: url,
            expectation: DownloadExpectation(minimumBytes: 1_000_000, expectedDigest: nil, requiredMagicBytes: DownloadExpectation.ggmlMagic)
        )
        #expect(outcome == .verifiedWithoutDigest)
    }

    @Test
    func validationAcceptsMatchingDigestAndRejectsMismatch() throws {
        let contents = Self.modelLikeData(byteCount: 2_000_000)
        let url = try Self.writeTemporaryFile(named: "digest.bin", contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }
        let expectation = DownloadExpectation(minimumBytes: 1_000_000, expectedDigest: nil, requiredMagicBytes: DownloadExpectation.ggmlMagic)

        let actual = try FileHasher.sha256HexDigest(ofFileAt: url)
        let matching = DownloadExpectation(
            minimumBytes: expectation.minimumBytes,
            expectedDigest: actual.uppercased(),
            requiredMagicBytes: expectation.requiredMagicBytes
        )
        #expect(try DownloadValidator.validate(fileAt: url, expectation: matching) == .verified)

        let wrong = DownloadExpectation(
            minimumBytes: expectation.minimumBytes,
            expectedDigest: String(repeating: "0", count: 64),
            requiredMagicBytes: expectation.requiredMagicBytes
        )
        #expect(try DownloadValidator.validate(fileAt: url, expectation: wrong) == .rejected(.digestMismatch(expectedDigest: String(repeating: "0", count: 64), actualDigest: actual)))
    }

    @Test
    func validationRejectsWrongMagicSignature() throws {
        let url = try Self.writeTemporaryFile(named: "html.bin", contents: Data("<!DOCTYPE html>".appending(String(repeating: "x", count: 2_000_000)).utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let outcome = try DownloadValidator.validate(
            fileAt: url,
            expectation: DownloadExpectation(minimumBytes: 1_000_000, expectedDigest: nil, requiredMagicBytes: DownloadExpectation.ggmlMagic)
        )
        #expect(outcome == .rejected(.unexpectedFileSignature))
    }

    // MARK: - Encoder extraction validation

    @Test
    func extractionValidatorAcceptsProperlyExtractedEncoder() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = try await Self.makeEncoderFixtureZip(in: root)
        let destination = root.appending(path: "dest", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try await ShellCommand.run(executable: "/usr/bin/ditto", arguments: ["-x", "-k", archive.path, destination.path])

        #expect(EncoderArchiveValidator.validateExtractedEncoder(in: destination))
    }

    @Test
    func extractionValidatorRejectsExtractionWithoutEncoderDirectory() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = root.appending(path: "unrelated", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: payload.appending(path: "other.txt"))

        let archive = root.appending(path: "unrelated.zip")
        _ = try await ShellCommand.run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", payload.path, archive.path])

        let destination = root.appending(path: "dest", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try await ShellCommand.run(executable: "/usr/bin/ditto", arguments: ["-x", "-k", archive.path, destination.path])

        #expect(!EncoderArchiveValidator.validateExtractedEncoder(in: destination))
    }

    // MARK: - Helpers

    private static func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func writeTemporaryFile(named name: String, contents: Data) throws -> URL {
        let url = try makeTemporaryDirectory().appending(path: name)
        try contents.write(to: url)
        return url
    }

    private static func modelLikeData(byteCount: Int) -> Data {
        var data = DownloadExpectation.ggmlMagic
        data.append(Data(count: max(0, byteCount - data.count)))
        return data
    }

    private static func writeModelLikeFile(named name: String, byteCount: Int) throws -> URL {
        try writeTemporaryFile(named: name, contents: modelLikeData(byteCount: byteCount))
    }

    private static func makeEncoderFixtureZip(in root: URL) async throws -> URL {
        let encoderDirectory = root.appending(path: EncoderArchiveValidator.encoderDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: encoderDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: encoderDirectory.appending(path: "metadata.json"))

        let archive = root.appending(path: "encoder.zip")
        _ = try await ShellCommand.run(executable: "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", encoderDirectory.path, archive.path])
        return archive
    }
}
