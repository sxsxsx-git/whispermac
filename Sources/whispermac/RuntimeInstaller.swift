import Foundation

enum RuntimeComponent: CaseIterable, Hashable {
    case whisperCLI
    case model
    case coreMLEncoder
}

struct RuntimeInstallResult {
    let modelPath: String?
}

enum RuntimeInstallerEvent {
    case status(String)
    case log(String)
    case progress(bytesDownloaded: Int64, totalBytes: Int64?)
}

enum RuntimeInstallerError: LocalizedError {
    case invalidDownloadResponse(String)
    case downloadTooSmall(minimumBytes: Int64, actualBytes: Int64)
    case invalidFileSignature
    case checksumMismatch(expectedDigest: String, actualDigest: String)
    case incompleteEncoderExtraction(String)

    var errorDescription: String? {
        switch self {
        case .invalidDownloadResponse(let url):
            return L.tr("error.invalid_download_response", url)
        case .downloadTooSmall(let minimumBytes, let actualBytes):
            return L.tr("error.download_too_small", actualBytes, minimumBytes)
        case .invalidFileSignature:
            return L.tr("error.download_invalid_signature")
        case .checksumMismatch(let expectedDigest, let actualDigest):
            return L.tr("error.download_checksum_mismatch", expectedDigest, actualDigest)
        case .incompleteEncoderExtraction(let path):
            return L.tr("error.encoder_extraction_incomplete", path)
        }
    }
}

enum RuntimeInstaller {
    private static let modelFileName = "ggml-large-v3-turbo.bin"
    private static let encoderArchiveFileName = "ggml-large-v3-turbo-encoder.mlmodelc.zip"
    private static let modelMinimumBytes: Int64 = 1_000_000_000
    private static let encoderArchiveMinimumBytes: Int64 = 10_000_000

    static func install(
        missing components: Set<RuntimeComponent>,
        onEvent: (@Sendable (RuntimeInstallerEvent) async -> Void)? = nil
    ) async throws -> RuntimeInstallResult {
        precondition(!components.contains(.whisperCLI), "whisper-cli must be bundled at packaging time")

        try FileManager.default.createDirectory(at: PathResolver.applicationSupportRoot, withIntermediateDirectories: true)

        var installedModelPath: String?
        if components.contains(.model) || components.contains(.coreMLEncoder) {
            await emit(.log(L.tr("log.runtime_download_component_model")), to: onEvent)
            installedModelPath = try await installModelAssets(onEvent: onEvent)
        }

        await emit(.log(L.tr("log.runtime_download_complete")), to: onEvent)
        return RuntimeInstallResult(modelPath: installedModelPath)
    }

    private static func installModelAssets(
        onEvent: (@Sendable (RuntimeInstallerEvent) async -> Void)? = nil
    ) async throws -> String {
        let modelsDirectory = PathResolver.downloadedRuntimeRoot
            .appending(path: "Models", directoryHint: .isDirectory)
        let modelDestination = modelsDirectory.appending(path: modelFileName)

        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let baseURL = HuggingFaceEndpoint.resolved()
        let digestSource = await fetchDigests(baseURL: baseURL, onEvent: onEvent)
        let digests = digestSource.digests

        await emit(.status(L.tr("status.runtime_downloading_model")), to: onEvent)
        let modelURL = HuggingFaceEndpoint.assetURL(fileName: modelFileName, baseURL: baseURL)
        await emit(.log(L.tr("log.runtime_download_source", modelURL.absoluteString)), to: onEvent)
        let modelExpectation = DownloadExpectation(
            minimumBytes: modelMinimumBytes,
            expectedDigest: digests[modelFileName],
            requiredMagicBytes: DownloadExpectation.ggmlMagic
        )
        let modelDownloadedURL = try await downloadVerified(
            from: modelURL,
            expectation: modelExpectation,
            digestSourceAvailable: digestSource.available,
            onEvent: onEvent
        )
        do {
            try replaceItem(at: modelDestination, with: modelDownloadedURL, executable: false)
        } catch {
            try? FileManager.default.removeItem(at: modelDownloadedURL)
            throw error
        }
        await emit(.log(L.tr("log.runtime_download_install", modelDestination.path)), to: onEvent)

        await emit(.status(L.tr("status.runtime_downloading_encoder")), to: onEvent)
        let encoderURL = HuggingFaceEndpoint.assetURL(fileName: encoderArchiveFileName, baseURL: baseURL)
        await emit(.log(L.tr("log.runtime_download_source", encoderURL.absoluteString)), to: onEvent)
        let encoderExpectation = DownloadExpectation(
            minimumBytes: encoderArchiveMinimumBytes,
            expectedDigest: digests[encoderArchiveFileName],
            requiredMagicBytes: nil
        )
        let encoderArchiveURL = try await downloadVerified(
            from: encoderURL,
            expectation: encoderExpectation,
            digestSourceAvailable: digestSource.available,
            onEvent: onEvent
        )
        defer { try? FileManager.default.removeItem(at: encoderArchiveURL) }

        let encoderDestination = modelsDirectory.appending(path: EncoderArchiveValidator.encoderDirectoryName, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: encoderDestination.path) {
            try FileManager.default.removeItem(at: encoderDestination)
        }

        await emit(.status(L.tr("status.runtime_extracting_encoder")), to: onEvent)
        await emit(.log(L.tr("log.runtime_download_extract")), to: onEvent)
        do {
            _ = try await ShellCommand.run(
                executable: "/usr/bin/ditto",
                arguments: ["-x", "-k", encoderArchiveURL.path, modelsDirectory.path]
            )
        } catch {
            try? FileManager.default.removeItem(at: encoderDestination)
            throw error
        }

        guard EncoderArchiveValidator.validateExtractedEncoder(in: modelsDirectory) else {
            try? FileManager.default.removeItem(at: encoderDestination)
            throw RuntimeInstallerError.incompleteEncoderExtraction(encoderDestination.path)
        }
        await emit(.log(L.tr("log.runtime_download_install", encoderDestination.path)), to: onEvent)

        return modelDestination.path
    }

    private static func fetchDigests(
        baseURL: URL,
        onEvent: (@Sendable (RuntimeInstallerEvent) async -> Void)?
    ) async -> (digests: [String: String], available: Bool) {
        do {
            let (data, response) = try await URLSession.shared.data(from: HuggingFaceEndpoint.treeAPIURL(baseURL: baseURL))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw RuntimeInstallerError.invalidDownloadResponse(baseURL.absoluteString)
            }
            return (try HuggingFaceTree.sha256DigestMap(from: data), true)
        } catch {
            await emit(.log(L.tr("warning.download_digest_unavailable")), to: onEvent)
            return ([:], false)
        }
    }

    private static func downloadVerified(
        from url: URL,
        expectation: DownloadExpectation,
        digestSourceAvailable: Bool,
        onEvent: (@Sendable (RuntimeInstallerEvent) async -> Void)?
    ) async throws -> URL {
        try Task.checkCancellation()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "whispermac-download-\(UUID().uuidString)")
        do {
            try await streamDownload(from: url, to: temporaryURL, onEvent: onEvent)
            switch try DownloadValidator.validate(fileAt: temporaryURL, expectation: expectation) {
            case .verified:
                break
            case .verifiedWithoutDigest:
                if digestSourceAvailable {
                    await emit(.log(L.tr("warning.download_digest_missing_for_file")), to: onEvent)
                }
            case .rejected(let rejection):
                throw rejectionError(from: rejection)
            }
            return temporaryURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func streamDownload(
        from url: URL,
        to destination: URL,
        onEvent: (@Sendable (RuntimeInstallerEvent) async -> Void)?
    ) async throws {
        let (progressStream, progressContinuation) = AsyncStream.makeStream(of: DownloadProgressTick.self)
        let delegate = RuntimeDownloadDelegate(destination: destination) { bytes, total in
            progressContinuation.yield(DownloadProgressTick(bytes: bytes, total: total))
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let downloadTask = session.downloadTask(with: url)

        let drain = Task {
            for await tick in progressStream {
                await emit(.progress(bytesDownloaded: tick.bytes, totalBytes: tick.total), to: onEvent)
            }
        }

        do {
            defer { progressContinuation.finish() }
            downloadTask.resume()
            let response = try await withTaskCancellationHandler {
                try await delegate.waitForCompletion()
            } onCancel: {
                downloadTask.cancel()
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RuntimeInstallerError.invalidDownloadResponse(url.absoluteString)
            }
            let expectedLength = http.expectedContentLength
            let totalBytes: Int64? = expectedLength > 0 ? expectedLength : nil
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            let downloadedBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            await emit(.progress(bytesDownloaded: downloadedBytes, totalBytes: totalBytes), to: onEvent)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }

        await drain.value
    }

    private static func rejectionError(from rejection: DownloadRejection) -> RuntimeInstallerError {
        switch rejection {
        case .belowMinimumSize(let minimumBytes, let actualBytes):
            return .downloadTooSmall(minimumBytes: minimumBytes, actualBytes: actualBytes)
        case .unexpectedFileSignature:
            return .invalidFileSignature
        case .digestMismatch(let expectedDigest, let actualDigest):
            return .checksumMismatch(expectedDigest: expectedDigest, actualDigest: actualDigest)
        }
    }

    private static func replaceItem(at destination: URL, with source: URL, executable: Bool) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
    }

    private static func emit(
        _ event: RuntimeInstallerEvent,
        to handler: (@Sendable (RuntimeInstallerEvent) async -> Void)?
    ) async {
        guard let handler else { return }
        await handler(event)
    }
}

private struct DownloadProgressTick: Sendable {
    let bytes: Int64
    let total: Int64?
}

// Bridges URLSessionDownloadTask callbacks into async/await. The task streams
// to disk itself (bounded memory); the delivered file is moved to `destination`
// inside didFinishDownloadingTo before the system deletes it.
// @unchecked Sendable: immutable `destination`/`onProgress`; mutable state is
// guarded by `lock`.
private final class RuntimeDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    private let onProgress: @Sendable (Int64, Int64?) -> Void
    private let lock = NSLock()
    private var completion: Result<URLResponse, Error>?
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var finalResponse: URLResponse?

    init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func waitForCompletion() async throws -> URLResponse {
        try await withCheckedThrowingContinuation { continuation in
            let settled: Result<URLResponse, Error>? = lock.withLock {
                if let completion {
                    return completion
                }
                self.continuation = continuation
                return nil
            }
            if let settled {
                continuation.resume(with: settled)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            lock.lock()
            finalResponse = downloadTask.response
            lock.unlock()
        } catch {
            settle(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            settle(.failure(error))
            return
        }
        guard let response = finalResponse else {
            settle(.failure(RuntimeInstallerError.invalidDownloadResponse(task.currentRequest?.url?.absoluteString ?? "")))
            return
        }
        settle(.success(response))
    }

    private func settle(_ result: Result<URLResponse, Error>) {
        let pending: CheckedContinuation<URLResponse, Error>? = lock.withLock {
            guard completion == nil else { return nil }
            completion = result
            let resumable = self.continuation
            self.continuation = nil
            return resumable
        }
        pending?.resume(with: result)
    }
}
