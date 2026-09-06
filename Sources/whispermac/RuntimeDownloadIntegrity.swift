import CryptoKit
import Foundation

enum FileHasher {
    static func sha256HexDigest(ofFileAt url: URL, chunkSize: Int = 1 << 20) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        var hasher = SHA256()
        while true {
            var chunk: Data?
            try autoreleasepool {
                chunk = try fileHandle.read(upToCount: chunkSize)
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct DownloadExpectation: Sendable {
    // GGML files start with 0x67676d6c ("ggml") serialized little-endian,
    // i.e. the ASCII bytes "lmgg".
    static let ggmlMagic = Data("lmgg".utf8)

    let minimumBytes: Int64
    let expectedDigest: String?
    let requiredMagicBytes: Data?
}

enum DownloadRejection: Equatable, Sendable {
    case belowMinimumSize(minimumBytes: Int64, actualBytes: Int64)
    case unexpectedFileSignature
    case digestMismatch(expectedDigest: String, actualDigest: String)
}

enum DownloadValidationOutcome: Equatable, Sendable {
    case verified
    case verifiedWithoutDigest
    case rejected(DownloadRejection)
}

enum DownloadValidator {
    static func validate(fileAt url: URL, expectation: DownloadExpectation) throws -> DownloadValidationOutcome {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actualBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard actualBytes >= expectation.minimumBytes else {
            return .rejected(.belowMinimumSize(minimumBytes: expectation.minimumBytes, actualBytes: actualBytes))
        }

        if let magic = expectation.requiredMagicBytes {
            guard try readHeader(of: url, length: magic.count) == magic else {
                return .rejected(.unexpectedFileSignature)
            }
        }

        guard let expectedDigest = expectation.expectedDigest?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return .verifiedWithoutDigest
        }

        let actualDigest = try FileHasher.sha256HexDigest(ofFileAt: url)
        guard actualDigest == expectedDigest else {
            return .rejected(.digestMismatch(expectedDigest: expectedDigest, actualDigest: actualDigest))
        }
        return .verified
    }

    private static func readHeader(of url: URL, length: Int) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        return fileHandle.readData(ofLength: length)
    }
}

enum EncoderArchiveValidator {
    static let encoderDirectoryName = "ggml-large-v3-turbo-encoder.mlmodelc"
    private static let metadataFileName = "metadata.json"

    static func validateExtractedEncoder(in destinationDirectory: URL) -> Bool {
        let metadataURL = destinationDirectory
            .appending(path: encoderDirectoryName, directoryHint: .isDirectory)
            .appending(path: metadataFileName)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: metadataURL.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }
}
