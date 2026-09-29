import Foundation
import Testing
@testable import whispermac

@Suite
struct VADModelTests {
    @Test
    func settingsUseDocumentedDefaultsAndClampInvalidRanges() {
        #expect(VADSettings.default == VADSettings())
        let settings = VADSettings(
            threshold: .infinity,
            minSpeechDurationMs: -1,
            minSilenceDurationMs: 99_000,
            speechPadMs: -50
        )
        #expect(settings.threshold == 0.5)
        #expect(settings.minSpeechDurationMs == 0)
        #expect(settings.minSilenceDurationMs == 10_000)
        #expect(settings.speechPadMs == 0)
    }

    @Test
    func settingsCodableRoundTrip() throws {
        let settings = VADSettings(isEnabled: true, modelPath: "/tmp/silero.bin", threshold: 0.63)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(VADSettings.self, from: data) == settings)
    }

    @MainActor
    @Test
    func appModelPersistsAndRestoresVADSettings() {
        let suiteName = "VADModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(defaults: defaults)
        model.vadSettings = VADSettings(
            isEnabled: true,
            modelPath: "/tmp/custom-silero.bin",
            threshold: 0.7,
            minSpeechDurationMs: 400,
            minSilenceDurationMs: 650,
            speechPadMs: 175
        )

        #expect(AppModel(defaults: defaults).vadSettings == model.vadSettings)
    }

    @MainActor
    @Test
    func appModelDisplaysAutomaticPathWithoutPersistingIt() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modelURL = root.appending(path: VADModelResolver.fileName)
        try writeValidModel(to: modelURL)
        let defaults = makeDefaults()

        let model = AppModel(defaults: defaults, vadModelSearchRoots: [root])

        #expect(model.vadModelDisplayPath == modelURL.path)
        #expect(model.isVADModelUsingAutomaticPath)
        #expect(model.vadSettings.modelPath.isEmpty)
        #expect((try? JSONDecoder().decode(VADSettings.self, from: defaults.data(forKey: "vadSettings") ?? Data()))?.modelPath.isEmpty ?? true)
    }

    @MainActor
    @Test
    func manualPathTakesPrecedenceAndCanRestoreAutomaticDiscovery() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let automaticURL = root.appending(path: VADModelResolver.fileName)
        let manualURL = root.appending(path: "manual-silero.bin")
        try writeValidModel(to: automaticURL)
        try writeValidModel(to: manualURL)
        let defaults = makeDefaults()
        let model = AppModel(defaults: defaults, vadModelSearchRoots: [root])

        model.vadSettings.modelPath = manualURL.path
        #expect(model.vadModelDisplayPath == manualURL.path)
        #expect(!model.isVADModelUsingAutomaticPath)

        model.restoreAutomaticVADModel()
        #expect(model.vadSettings.modelPath.isEmpty)
        #expect(model.vadModelDisplayPath == automaticURL.path)
        #expect(model.isVADModelUsingAutomaticPath)
    }

    @MainActor
    @Test
    func automaticDisplayIsEmptyWhenNoModelExists() {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let defaults = makeDefaults()
        let model = AppModel(defaults: defaults, vadModelSearchRoots: [root])

        #expect(model.resolvedVADModelPath.isEmpty)
        #expect(model.vadModelDisplayPath.isEmpty)
        #expect(model.isVADModelUsingAutomaticPath)
        #expect(!model.hasResolvableVADModel)
        #expect(model.vadSettings.modelPath.isEmpty)
    }

    @MainActor
    @Test
    func invalidManualPathRemainsManualAndUnavailable() {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let defaults = makeDefaults()
        let model = AppModel(defaults: defaults, vadModelSearchRoots: [root])
        model.vadSettings.modelPath = root.appending(path: "missing-model.bin").path

        #expect(model.vadModelDisplayPath == root.appending(path: "missing-model.bin").path)
        #expect(!model.isVADModelUsingAutomaticPath)
        #expect(!model.hasResolvableVADModel)
        #expect(model.resolvedVADModelPath.isEmpty)
    }

    @MainActor
    @Test
    func downloadingVADInAutomaticModeKeepsPathUnsetAndAutomaticallyResolvable() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installedModel = root.appending(path: VADModelResolver.fileName)
        let defaults = makeDefaults()
        let model = AppModel(
            defaults: defaults,
            vadModelSearchRoots: [root],
            huggingFaceEnvironment: [:],
            vadModelInstaller: { _, _ in
                var contents = VADModelResolver.requiredHeader
                contents.append(Data(repeating: 0, count: Int(VADModelResolver.minimumBytes) - contents.count))
                try contents.write(to: installedModel)
                return installedModel.path
            }
        )
        model.vadSettings.isEnabled = true
        #expect(model.isVADModelUsingAutomaticPath)
        #expect(!model.hasResolvableVADModel)

        model.downloadVADModel()
        await model.waitForVADDownload()

        #expect(model.vadSettings.modelPath.isEmpty)
        #expect(model.isVADModelUsingAutomaticPath)
        #expect(model.resolvedVADModelPath == installedModel.path)
        #expect(model.hasResolvableVADModel)
        let persisted = try #require(defaults.data(forKey: "vadSettings"))
        #expect(try JSONDecoder().decode(VADSettings.self, from: persisted).modelPath.isEmpty)
    }

    @MainActor
    @Test
    func downloadingDefaultVADFromInvalidManualPathRestoresAutomaticMode() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installedModel = root.appending(path: VADModelResolver.fileName)
        let missingManualPath = root.appending(path: "moved-away-model.bin").path
        let defaults = makeDefaults()
        let model = AppModel(
            defaults: defaults,
            vadModelSearchRoots: [root],
            huggingFaceEnvironment: [:],
            vadModelInstaller: { _, _ in
                var contents = VADModelResolver.requiredHeader
                contents.append(Data(repeating: 0, count: Int(VADModelResolver.minimumBytes) - contents.count))
                try contents.write(to: installedModel)
                return installedModel.path
            }
        )
        model.vadSettings = VADSettings(isEnabled: true, modelPath: missingManualPath)
        #expect(!model.isVADModelUsingAutomaticPath)
        #expect(!model.hasResolvableVADModel)

        model.downloadVADModel()
        await model.waitForVADDownload()

        #expect(model.vadSettings.modelPath.isEmpty)
        #expect(model.isVADModelUsingAutomaticPath)
        #expect(model.resolvedVADModelPath == installedModel.path)
        let persisted = try #require(defaults.data(forKey: "vadSettings"))
        #expect(try JSONDecoder().decode(VADSettings.self, from: persisted).modelPath.isEmpty)
    }

    @Test
    func automaticDiscoveryFindsPreferredModelName() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appending(path: VADModelResolver.fileName)
        try writeValidModel(to: model)
        #expect(VADModelResolver.resolve("", searchRoots: [root]) == model.path)
    }

    @Test
    func manualPathIsAcceptedAndMissingPathIsRejected() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appending(path: "custom-silero.bin")
        try writeValidModel(to: model)
        #expect(VADModelResolver.resolve(model.path) == model.path)
        #expect(VADModelResolver.resolve(root.appending(path: "missing.bin").path).isEmpty)
    }

    @Test
    func modelValidationRequiresSileroGGMLHeaderAndPlausibleSize() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let wrongModel = root.appending(path: "whisper-model.bin")
        var whisperHeader = DownloadExpectation.ggmlMagic
        whisperHeader.append(Data(repeating: 0, count: Int(VADModelResolver.minimumBytes) - whisperHeader.count))
        try whisperHeader.write(to: wrongModel)
        #expect(!VADModelResolver.isValidModel(at: wrongModel))

        let oversizedModel = root.appending(path: "oversized.bin")
        try VADModelResolver.requiredHeader.write(to: oversizedModel)
        let oversizedHandle = try FileHandle(forWritingTo: oversizedModel)
        try oversizedHandle.truncate(atOffset: UInt64(VADModelResolver.maximumBytes + 1))
        try oversizedHandle.close()
        #expect(!VADModelResolver.isValidModel(at: oversizedModel))
    }

    @Test
    func vadDownloadURLUsesOfficialRepositoryAndAsset() {
        let url = HuggingFaceEndpoint.assetURL(
            fileName: VADModelResolver.fileName,
            baseURL: HuggingFaceEndpoint.defaultBaseURL,
            repository: "ggml-org/whisper-vad"
        )
        #expect(url.absoluteString == "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin?download=true")
        #expect(HuggingFaceEndpoint.treeAPIURL(
            baseURL: HuggingFaceEndpoint.defaultBaseURL,
            repository: "ggml-org/whisper-vad"
        ).absoluteString == "https://huggingface.co/api/models/ggml-org/whisper-vad/tree/main?recursive=true")
    }

    @Test
    func vadFileValidationUsesCompactModelSizeThreshold() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appending(path: "small.bin")
        try Data(repeating: 1, count: Int(VADModelResolver.minimumBytes) - 1).write(to: model)
        let tooSmall = try DownloadValidator.validate(
            fileAt: model,
            expectation: DownloadExpectation(
                minimumBytes: VADModelResolver.minimumBytes,
                expectedDigest: nil,
                requiredMagicBytes: nil
            )
        )
        #expect(tooSmall == .rejected(.belowMinimumSize(
            minimumBytes: VADModelResolver.minimumBytes,
            actualBytes: VADModelResolver.minimumBytes - 1
        )))
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "VADModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func writeValidModel(to url: URL) throws {
        var data = VADModelResolver.requiredHeader
        data.append(Data(repeating: 0, count: Int(VADModelResolver.minimumBytes) - data.count))
        try data.write(to: url)
    }
}
