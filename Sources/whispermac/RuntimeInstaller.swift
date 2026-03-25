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
}

enum RuntimeInstallerError: LocalizedError {
    case invalidDownloadResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidDownloadResponse(let url):
            return L.tr("error.invalid_download_response", url)
        }
    }
}

enum RuntimeInstaller {
    private static let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!
    private static let encoderURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-encoder.mlmodelc.zip?download=true")!

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
        let modelDestination = modelsDirectory.appending(path: "ggml-large-v3-turbo.bin")

        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        await emit(.status(L.tr("status.runtime_downloading_model")), to: onEvent)
        await emit(.log(L.tr("log.runtime_download_source", modelURL.absoluteString)), to: onEvent)
        let modelDownloadedURL = try await download(from: modelURL)
        try replaceItem(at: modelDestination, with: modelDownloadedURL, executable: false)
        await emit(.log(L.tr("log.runtime_download_install", modelDestination.path)), to: onEvent)

        await emit(.status(L.tr("status.runtime_downloading_encoder")), to: onEvent)
        await emit(.log(L.tr("log.runtime_download_source", encoderURL.absoluteString)), to: onEvent)
        let encoderArchiveURL = try await download(from: encoderURL)

        let encoderDestination = modelsDirectory.appending(path: "ggml-large-v3-turbo-encoder.mlmodelc", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: encoderDestination.path) {
            try FileManager.default.removeItem(at: encoderDestination)
        }

        await emit(.status(L.tr("status.runtime_extracting_encoder")), to: onEvent)
        await emit(.log(L.tr("log.runtime_download_extract")), to: onEvent)
        _ = try await ShellCommand.run(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", encoderArchiveURL.path, modelsDirectory.path]
        )
        await emit(.log(L.tr("log.runtime_download_install", encoderDestination.path)), to: onEvent)

        return modelDestination.path
    }

    private static func download(from url: URL) async throws -> URL {
        let (downloadedURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RuntimeInstallerError.invalidDownloadResponse(url.absoluteString)
        }
        return downloadedURL
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
