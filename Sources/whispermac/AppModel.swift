import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private static let repositoryURL = URL(string: "https://github.com/sxsxsx-git/whispermac")!

    @Published var inputFiles: [URL]
    @Published var appLanguage: AppLanguage {
        didSet {
            L.setAppLanguage(appLanguage)
            refreshLocalizedContent()
        }
    }
    @Published var outputDirectoryPath: String {
        didSet { store(outputDirectoryPath, forKey: Keys.outputDirectoryPath) }
    }
    @Published var whisperCLIPath: String {
        didSet { store(whisperCLIPath, forKey: Keys.whisperCLIPath) }
    }
    @Published var modelPath: String {
        didSet { store(modelPath, forKey: Keys.modelPath) }
    }
    @Published var accelerationMode: AccelerationMode {
        didSet { store(accelerationMode.rawValue, forKey: Keys.accelerationMode) }
    }
    @Published var outputFormats: Set<OutputFormat> {
        didSet { store(Array(outputFormats).map(\.rawValue).sorted(), forKey: Keys.outputFormats) }
    }
    @Published var sourceLanguage: String {
        didSet { store(sourceLanguage, forKey: Keys.sourceLanguage) }
    }
    @Published var translatesToEnglish: Bool {
        didSet { store(translatesToEnglish, forKey: Keys.translatesToEnglish) }
    }
    @Published var logs: [String]
    @Published var isRunning = false
    @Published var isCancelling = false
    @Published var statusText = ""
    @Published var overallProgress = 0.0
    @Published var currentFileProgress = 0.0
    @Published var currentFileName = ""
    @Published var currentStageDescription = ""
    @Published var currentTranscriptionProgress = 0.0
    @Published var isDownloadingRuntime = false
    @Published var isRuntimeDownloadPromptPresented = false
    @Published var downloadedBytes: Int64 = 0
    @Published var downloadTotalBytes: Int64?
    @Published private(set) var previewFiles: [TranscriptPreviewFile] = []
    @Published private(set) var selectedPreviewFileID: URL?
    @Published private(set) var previewSegments: [TranscriptSegment] = []
    @Published private(set) var isLoadingPreview = false
    @Published private(set) var liveSegments: [TranscriptSegment] = []
    @Published private(set) var historyEntries: [HistoryEntry] = []

    private let defaults = UserDefaults.standard
    private var hasPresentedInitialRuntimePrompt = false
    private var transcriptionTask: Task<Void, Never>?
    private var runtimeDownloadTask: Task<Void, Never>?
    private var previewLoadGeneration = 0
    private lazy var historyStore = TranscriptionHistoryStore()
    private let completionNotifier: CompletionNotifier
    private var keepAwakeToken: KeepAwakeToken?

    init(completionNotifier: CompletionNotifier = CompletionNotifier()) {
        self.completionNotifier = completionNotifier
        let defaults = UserDefaults.standard
        let guessed = PathResolver.guessDefaults()
        let storedWhisperCLIPath = defaults.string(forKey: Keys.whisperCLIPath) ?? ""
        let resolvedWhisperCLIPath = PathResolver.resolveWhisperCLIPath(storedWhisperCLIPath)
        let initialWhisperCLIPath = resolvedWhisperCLIPath.isEmpty
            ? (storedWhisperCLIPath.isEmpty ? guessed.whisperCLIPath : storedWhisperCLIPath)
            : resolvedWhisperCLIPath
        let storedModelPath = defaults.string(forKey: Keys.modelPath) ?? ""
        let resolvedModelPath = PathResolver.resolveModelPath(storedModelPath, whisperCLIPath: initialWhisperCLIPath)
        let initialModelPath = resolvedModelPath.isEmpty
            ? (storedModelPath.isEmpty ? guessed.modelPath : storedModelPath)
            : resolvedModelPath
        let storedFormats = defaults.array(forKey: Keys.outputFormats) as? [String]
        let storedAccelerationMode = defaults.string(forKey: Keys.accelerationMode)
        var selectedFormats = Set((storedFormats ?? []).compactMap(OutputFormat.init(rawValue:)))
        if selectedFormats.isEmpty {
            selectedFormats = [.txt, .srt]
        }
        let storedSourceLanguage = defaults.string(forKey: Keys.sourceLanguage) ?? WhisperLanguage.autoCode
        let initialSourceLanguage = WhisperLanguage.isSupported(storedSourceLanguage)
            ? storedSourceLanguage
            : WhisperLanguage.autoCode

        inputFiles = []
        appLanguage = AppLanguage(storedValue: defaults.string(forKey: Keys.appLanguage))
        outputDirectoryPath = defaults.string(forKey: Keys.outputDirectoryPath) ?? ""
        whisperCLIPath = initialWhisperCLIPath
        modelPath = initialModelPath
        accelerationMode = AccelerationMode(rawValue: storedAccelerationMode ?? "") ?? .gpuAndANE
        outputFormats = selectedFormats
        sourceLanguage = initialSourceLanguage
        translatesToEnglish = defaults.bool(forKey: Keys.translatesToEnglish)

        logs = [
            L.tr("log.default_model"),
            L.tr("log.audio_preprocessor_switched"),
            L.tr("log.coreml_auto"),
        ]

        // Resolution stays a runtime overlay: UserDefaults only ever holds what
        // the user explicitly picked, so a launch-time guess is never silently
        // persisted over the stored setting.

        loadHistoryFromStore()
    }

    var logsText: String {
        logs.joined(separator: "\n")
    }

    var canStart: Bool {
        let resolvedWhisperCLIPath = self.resolvedWhisperCLIPath
        let resolvedModelPath = self.resolvedModelPath

        return !isRunning &&
            !isDownloadingRuntime &&
            !inputFiles.isEmpty &&
            !resolvedWhisperCLIPath.isEmpty &&
            !resolvedModelPath.isEmpty &&
            !outputFormats.isEmpty
    }

    var downloadProgress: Double? {
        guard let totalBytes = downloadTotalBytes, totalBytes > 0, downloadedBytes > 0 else { return nil }
        return min(Double(downloadedBytes) / Double(totalBytes), 1.0)
    }

    var isBusy: Bool {
        isRunning || isDownloadingRuntime
    }

    var outputDirectoryDisplayText: String {
        let trimmed = outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let firstInput = inputFiles.first {
            return L.tr("display.follow_input_dir", firstInput.deletingLastPathComponent().path)
        }
        return L.tr("display.follow_input_default")
    }

    var configurationLooksReady: Bool {
        !resolvedModelPath.isEmpty &&
        !resolvedWhisperCLIPath.isEmpty
    }

    var missingRuntimeComponents: Set<RuntimeComponent> {
        runtimeComponentsMissing(whisperCLIPath: whisperCLIPath, modelPath: modelPath)
    }

    var downloadableRuntimeComponents: Set<RuntimeComponent> {
        missingRuntimeComponents.subtracting([.whisperCLI])
    }

    var runtimeDownloadPromptTitle: String {
        L.tr("alert.runtime_missing_title")
    }

    var runtimeDownloadPromptMessage: String {
        downloadableRuntimeComponents.isEmpty ? "" : L.tr("alert.runtime_missing_message_model")
    }

    var accelerationSummary: String {
        let resolvedWhisperCLIPath = self.resolvedWhisperCLIPath
        guard !resolvedWhisperCLIPath.isEmpty else {
            return L.tr("summary.runtime_missing_cli")
        }

        let resolvedModelPath = self.resolvedModelPath
        guard !resolvedModelPath.isEmpty else {
            return L.tr("summary.model_assets_missing")
        }

        let modelURL = URL(fileURLWithPath: resolvedModelPath)
        let coreMLURL = OutputPaths.coreMLModelURL(for: modelURL)
        let hasCoreML = FileManager.default.fileExists(atPath: coreMLURL.path)

        if accelerationMode == .gpuAndANE && !hasCoreML {
            return L.tr("summary.coreml_missing_download")
        }
        if accelerationMode == .gpuAndANE && hasCoreML {
            return L.tr("summary.mode_gpu_ane")
        }
        if hasCoreML {
            return L.tr("summary.mode_pure_gpu_coreml_present")
        }
        return L.tr("summary.mode_pure_gpu")
    }

    var accelerationDetail: String {
        switch accelerationMode {
        case .pureGPU:
            return L.tr("detail.pure_gpu")
        case .gpuAndANE:
            return L.tr("detail.gpu_ane")
        }
    }

    func chooseInputFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PanelHelper.supportedMediaTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return }
        addMediaURLs(panel.urls)
    }

    func addMediaURLs(_ urls: [URL]) {
        let additions = PanelHelper.mediaFileAdditions(from: urls, existing: inputFiles)
        guard !additions.isEmpty else { return }

        inputFiles.append(contentsOf: additions)

        if outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outputDirectoryPath = ""
        }
    }

    func clearInputFiles() {
        guard !isRunning else { return }
        inputFiles.removeAll()
    }

    func removeInputFile(_ url: URL) {
        guard !isRunning else { return }
        inputFiles.removeAll { $0 == url }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectoryPath = url.path
    }

    func chooseWhisperCLI() {
        if let url = PanelHelper.chooseBinary() {
            whisperCLIPath = url.path
            PathResolver.invalidateCaches()
        }
    }

    func chooseModel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.nameFieldStringValue = "ggml-large-v3-turbo.bin"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        modelPath = url.path
        PathResolver.invalidateCaches()
    }

    func openOutputDirectory() {
        let directoryPath = resolvedOutputDirectoryPath(for: inputFiles.first)
        guard !directoryPath.isEmpty else { return }
        let directory = URL(fileURLWithPath: directoryPath)
        NSWorkspace.shared.open(directory)
    }

    func openProjectREADME() {
        let bundledREADME = Bundle.main.resourceURL?.appending(path: "README.md")
        let readmeURL = bundledREADME.flatMap {
            FileManager.default.fileExists(atPath: $0.path) ? $0 : nil
        } ?? PathResolver.projectRoot.appending(path: "README.md")
        guard FileManager.default.fileExists(atPath: readmeURL.path) else { return }
        NSWorkspace.shared.open(readmeURL)
    }

    func openProjectRepository() {
        NSWorkspace.shared.open(Self.repositoryURL)
    }

    func refreshLocalizedContent() {
        store(appLanguage.rawValue, forKey: Keys.appLanguage)

        if !isRunning && !isDownloadingRuntime {
            statusText = ""
            currentStageDescription = ""
            logs = [
                L.tr("log.default_model"),
                L.tr("log.audio_preprocessor_switched"),
                L.tr("log.coreml_auto"),
            ]
        }

        objectWillChange.send()
    }

    func promptToDownloadMissingRuntimeIfNeeded() {
        guard !hasPresentedInitialRuntimePrompt else { return }
        hasPresentedInitialRuntimePrompt = true
        promptToDownloadMissingRuntime(force: false)
    }

    func promptToDownloadMissingRuntime(force: Bool) {
        guard !isDownloadingRuntime else { return }
        guard !downloadableRuntimeComponents.isEmpty else { return }
        if force || !isRuntimeDownloadPromptPresented {
            isRuntimeDownloadPromptPresented = true
        }
    }

    func dismissRuntimeDownloadPrompt() {
        isRuntimeDownloadPromptPresented = false
    }

    func startRuntimeDownload() {
        guard !isDownloadingRuntime else { return }
        let missing = downloadableRuntimeComponents
        guard !missing.isEmpty else { return }

        isRuntimeDownloadPromptPresented = false

        runtimeDownloadTask = Task { [weak self] in
            await self?.downloadMissingRuntime(missing)
        }
    }

    func cancelRuntimeDownload() {
        guard isDownloadingRuntime else { return }
        runtimeDownloadTask?.cancel()
    }

    func setFormat(_ format: OutputFormat, enabled: Bool) {
        if enabled {
            outputFormats.insert(format)
            return
        }
        if outputFormats.count > 1 {
            outputFormats.remove(format)
        }
    }

    func startTranscription() {
        guard canStart else {
            promptToDownloadMissingRuntime(force: true)
            return
        }

        let resolvedWhisperCLIPath = self.resolvedWhisperCLIPath
        let resolvedModelPath = self.resolvedModelPath

        let snapshot = AppConfigurationSnapshot(
            inputFiles: inputFiles,
            outputDirectoryPath: outputDirectoryPath,
            whisperCLIPath: resolvedWhisperCLIPath,
            modelPath: resolvedModelPath,
            accelerationMode: accelerationMode,
            outputFormats: outputFormats,
            sourceLanguage: sourceLanguage,
            translatesToEnglish: translatesToEnglish
        )

        transcriptionTask = Task {
            await runTranscription(snapshot)
        }
    }

    func cancelTranscription() {
        guard isRunning, !isCancelling else { return }
        isCancelling = true
        transcriptionTask?.cancel()
    }

    private func runTranscription(_ snapshot: AppConfigurationSnapshot) async {
        isRunning = true
        keepAwakeToken = KeepAwakeController.acquire(reason: KeepAwakeController.batchReason)
        let notifier = completionNotifier
        Task { await notifier.prepareForRun() }
        let runStartedAt = Date()
        clearPreviews()
        liveSegments = []
        logs.removeAll()
        statusText = L.tr("status.preparing_start")
        overallProgress = 0
        currentFileProgress = 0
        currentFileName = ""
        currentStageDescription = ""
        currentTranscriptionProgress = 0

        let service = TranscriptionService()
        let modelPlan: RuntimeModelPlan
        var successCount = 0
        var failureCount = 0
        var wasCancelled = false

        do {
            modelPlan = try RuntimeModelResolver.prepare(
                modelPath: snapshot.modelPath,
                requestedMode: snapshot.accelerationMode
            )
        } catch {
            appendLog(error.localizedDescription)
            statusText = L.tr("status.prepare_failed")
            await finishTranscriptionRun(failureCount: snapshot.inputFiles.count)
            return
        }

        appendLog(L.tr("log.start_files", snapshot.inputFiles.count))
        appendLog(L.tr("log.requested_mode", snapshot.accelerationMode.title))
        appendLog(L.tr("log.effective_mode", modelPlan.effectiveMode.title))
        appendLog(L.tr("log.model_path", modelPlan.originalModelPath))
        if modelPlan.executionModelPath != modelPlan.originalModelPath {
            appendLog(L.tr("log.runtime_model_path", modelPlan.executionModelPath))
        }
        appendLog(L.tr("log.coreml_encoder", modelPlan.coreMLAvailable ? modelPlan.coreMLModelPath : L.tr("log.not_found")))
        for note in modelPlan.notes {
            appendLog(note)
        }
        if snapshot.outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog(L.tr("log.output_directory_follow"))
        } else {
            appendLog(L.tr("log.output_directory", PathResolver.expandingTilde(snapshot.outputDirectoryPath)))
        }
        appendLog(L.tr("log.output_formats", snapshot.outputFormats.map(\.rawValue).sorted().joined(separator: ", ")))

        let totalFiles = snapshot.inputFiles.count
        let batchInputs = snapshot.inputFiles.map { inputURL in
            BatchTranscriptionInput(
                inputURL: inputURL,
                outputDirectory: URL(fileURLWithPath: resolvedOutputDirectoryPath(for: inputURL, overridePath: snapshot.outputDirectoryPath))
            )
        }

        do {
            let reports = try await service.transcribeBatch(
                inputs: batchInputs,
                whisperCLIPath: snapshot.whisperCLIPath,
                modelPath: modelPlan.executionModelPath,
                formats: snapshot.outputFormats,
                sourceLanguage: snapshot.sourceLanguage,
                translatesToEnglish: snapshot.translatesToEnglish,
                onInputStageChange: { [weak self] index, stage in
                    await MainActor.run {
                        guard let self else { return }
                        self.statusText = L.tr("status.processing", index + 1, totalFiles)
                        self.currentFileName = snapshot.inputFiles[index].lastPathComponent
                        switch stage {
                        case .preparing:
                            self.currentStageDescription = stage.description
                            self.currentFileProgress = 0.03
                        case .extractingAudio:
                            self.currentStageDescription = stage.description
                            self.currentFileProgress = max(self.currentFileProgress, 0.12)
                        default:
                            break
                        }
                        let preparationProgress = min((Double(index) + self.currentFileProgress) / Double(totalFiles), 1.0)
                        self.overallProgress = preparationProgress * 0.18
                    }
                },
                onStageChange: { [weak self] stage in
                    await MainActor.run {
                        guard let self else { return }
                        switch stage {
                        case .transcribing:
                            self.statusText = L.tr("stage.transcribing_batch", totalFiles)
                            self.currentFileName = ""
                            self.currentStageDescription = stage.description
                            self.currentFileProgress = max(self.currentFileProgress, 0.18)
                        case .finished:
                            self.currentStageDescription = stage.description
                            self.currentTranscriptionProgress = 1
                            self.currentFileProgress = 1
                            self.overallProgress = 1
                        default:
                            break
                        }
                    }
                },
                onLog: { [weak self] line in
                    await MainActor.run {
                        self?.appendLog(line)
                    }
                },
                onTranscriptionProgress: { [weak self] progress in
                    await MainActor.run {
                        guard let self else { return }
                        self.currentTranscriptionProgress = progress
                        self.currentStageDescription = L.tr("stage.transcribing_progress", Int(progress * 100))
                        self.currentFileProgress = max(0.18, 0.18 + 0.82 * progress)
                        self.overallProgress = min(0.18 + 0.82 * progress, 1.0)
                    }
                },
                onSegment: { [weak self] segment in
                    await MainActor.run {
                        self?.appendLiveSegment(segment)
                    }
                }
            )

            successCount = totalFiles
            if let whisperCommand = reports.first?.whisperCommand {
                appendLog(L.tr("log.whisper_command", whisperCommand))
            }
            for (index, report) in reports.enumerated() {
                appendLog(L.tr("log.completed_file", snapshot.inputFiles[index].lastPathComponent))
                appendLog(L.tr("log.output_directory", batchInputs[index].outputDirectory.path))
                appendLog(L.tr("log.audio_preparation_command", report.audioPreparationCommand))
                if !report.outputFiles.isEmpty {
                    appendLog(L.tr("log.generated_files"))
                    for outputFile in report.outputFiles {
                        appendLog("  \(outputFile.path)")
                    }
                }
            }
            installPreviewFiles(from: reports, inputs: batchInputs)
            recordHistoryEntries(
                reports: reports,
                inputFiles: snapshot.inputFiles,
                outputDirectories: batchInputs.map(\.outputDirectory),
                durationSeconds: Date().timeIntervalSince(runStartedAt)
            )
        } catch is CancellationError {
            wasCancelled = true
            appendLog(L.tr("log.cancelled"))
        } catch {
            failureCount = totalFiles
            currentFileProgress = 1
            currentStageDescription = L.tr("stage.failed")
            appendLog(L.tr("log.failed_batch"))
            appendLog(error.localizedDescription)
        }

        appendLog(String(repeating: "-", count: 72))

        if wasCancelled {
            statusText = L.tr("status.cancelled")
            currentStageDescription = L.tr("status.cancelled")
        } else {
            statusText = L.tr("log.completed_summary", successCount, failureCount)
            currentStageDescription = failureCount == 0 ? L.tr("stage.all_done") : L.tr("stage.processing_finished")
            currentFileProgress = snapshot.inputFiles.isEmpty ? 0 : 1
            overallProgress = snapshot.inputFiles.isEmpty ? 0 : 1
        }
        await finishTranscriptionRun(
            successCount: successCount,
            failureCount: failureCount,
            wasCancelled: wasCancelled
        )
    }

    private func installPreviewFiles(from reports: [TranscriptionReport], inputs: [BatchTranscriptionInput]) {
        var files: [TranscriptPreviewFile] = []
        files.reserveCapacity(reports.count)
        for (index, report) in reports.enumerated() {
            guard index < inputs.count else { continue }
            let displayName = inputs[index].inputURL.lastPathComponent
            for output in report.outputFiles where output.pathExtension.lowercased() == "srt" {
                files.append(TranscriptPreviewFile(id: output, url: output, displayName: displayName))
            }
        }
        guard let last = files.last else { return }
        previewFiles = files
        selectedPreviewFileID = last.id
        loadPreviewSegments(for: last.id)
    }

    func selectPreviewFile(id: URL?) {
        guard id != selectedPreviewFileID else { return }
        selectedPreviewFileID = id
        loadPreviewSegments(for: id)
    }

    private func loadPreviewSegments(for fileID: URL?) {
        previewLoadGeneration += 1
        let generation = previewLoadGeneration
        guard let fileID, let file = previewFiles.first(where: { $0.id == fileID }) else {
            previewSegments = []
            isLoadingPreview = false
            return
        }
        let url = file.url
        isLoadingPreview = true
        previewSegments = []
        Task { [weak self] in
            let segments = await Self.readSegments(url: url)
            guard let self, generation == self.previewLoadGeneration else { return }
            self.previewSegments = segments
            self.isLoadingPreview = false
        }
    }

    /// Runs off the main actor (nonisolated async functions execute on the global
    /// executor); read failures yield an empty list so the UI shows a hint instead.
    private nonisolated static func readSegments(url: URL) async -> [TranscriptSegment] {
        (try? SRTParser.load(at: url)) ?? []
    }

    private func clearPreviews() {
        previewLoadGeneration += 1
        previewFiles = []
        selectedPreviewFileID = nil
        previewSegments = []
        isLoadingPreview = false
    }

    /// Hands the live section over to the static preview (or to nothing after a
    /// cancellation); the UI hides the live section once isRunning flips false.
    private func appendLiveSegment(_ segment: TranscriptSegment) {
        liveSegments = TranscriptPreview.appendCapped(
            segment,
            to: liveSegments,
            limit: TranscriptPreview.liveSegmentLimit
        )
    }

    // MARK: - History

    func revealHistoryEntryInFinder(_ entry: HistoryEntry) {
        if let firstOutputPath = entry.outputFilePaths.first,
           FileManager.default.fileExists(atPath: firstOutputPath) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: firstOutputPath)])
            return
        }

        let outputDirectory = URL(fileURLWithPath: entry.outputDirectoryPath)
        guard FileManager.default.fileExists(atPath: outputDirectory.path) else { return }
        NSWorkspace.shared.open(outputDirectory)
    }

    func clearHistory() {
        historyEntries = []
        let store = historyStore
        Task {
            await Self.eraseHistory(store: store)
        }
    }

    private func loadHistoryFromStore() {
        let store = historyStore
        Task { [weak self] in
            let entries = await Self.readHistory(store: store)
            self?.historyEntries = entries
        }
    }

    /// History is best-effort: recording failures are swallowed and the store
    /// is simply re-read so the published list matches what is on disk.
    private func recordHistoryEntries(
        reports: [TranscriptionReport],
        inputFiles: [URL],
        outputDirectories: [URL],
        durationSeconds: Double
    ) {
        guard !reports.isEmpty else { return }
        let entries = TranscriptionHistoryStore.makeEntries(
            reports: reports,
            inputFiles: inputFiles,
            outputDirectories: outputDirectories,
            durationSeconds: durationSeconds
        )
        let store = historyStore
        Task { [weak self] in
            let loaded = await Self.writeHistory(store: store, entries: entries)
            self?.historyEntries = loaded
        }
    }

    /// Runs off the main actor (nonisolated async functions execute on the
    /// global executor), keeping history file I/O out of the UI.
    private nonisolated static func readHistory(store: TranscriptionHistoryStore) async -> [HistoryEntry] {
        store.load()
    }

    private nonisolated static func writeHistory(store: TranscriptionHistoryStore, entries: [HistoryEntry]) async -> [HistoryEntry] {
        try? store.record(entries)
        return store.load()
    }

    private nonisolated static func eraseHistory(store: TranscriptionHistoryStore) async {
        try? store.clear()
    }

    /// The single funnel every run path (success/failure/cancel) flows through:
    /// releases the keep-awake assertion by dropping it and posts the completion
    /// notification unless the batch was cancelled.
    private func finishTranscriptionRun(
        successCount: Int = 0,
        failureCount: Int = 0,
        wasCancelled: Bool = false
    ) async {
        liveSegments = []
        isRunning = false
        isCancelling = false
        transcriptionTask = nil
        keepAwakeToken = nil
        await completionNotifier.notifyBatchFinished(
            successCount: successCount,
            failureCount: failureCount,
            wasCancelled: wasCancelled
        )
    }

    private func downloadMissingRuntime(_ missing: Set<RuntimeComponent>) async {
        isDownloadingRuntime = true
        downloadedBytes = 0
        downloadTotalBytes = nil
        statusText = L.tr("status.runtime_preparing_download")
        appendLog(L.tr("log.runtime_download_start"))

        do {
            let result = try await RuntimeInstaller.install(missing: missing) { [weak self] event in
                await MainActor.run {
                    guard let self else { return }
                    switch event {
                    case .status(let status):
                        self.statusText = status
                    case .log(let line):
                        self.appendLog(line)
                    case .progress(let bytesDownloaded, let totalBytes):
                        self.downloadedBytes = bytesDownloaded
                        self.downloadTotalBytes = totalBytes
                    }
                }
            }

            // The installer placed new files on disk; cached resolution
            // results for unchanged inputs must not shadow them.
            PathResolver.invalidateCaches()

            if let modelPath = result.modelPath {
                self.modelPath = modelPath
            }

            statusText = L.tr("status.runtime_ready")
        } catch is CancellationError {
            statusText = L.tr("status.download_cancelled")
            appendLog(L.tr("log.download_cancelled"))
        } catch {
            appendLog(error.localizedDescription)
            statusText = L.tr("status.runtime_download_failed")
        }

        isDownloadingRuntime = false
        runtimeDownloadTask = nil
    }

    private func appendLog(_ line: String) {
        logs.append(line)
    }

    private func runtimeComponentsMissing(whisperCLIPath: String, modelPath: String) -> Set<RuntimeComponent> {
        var missing = Set<RuntimeComponent>()
        let resolvedWhisperCLIPath = PathResolver.resolveWhisperCLIPath(whisperCLIPath)
        let resolvedModelPath = PathResolver.resolveModelPath(modelPath, whisperCLIPath: resolvedWhisperCLIPath)

        if resolvedWhisperCLIPath.isEmpty {
            missing.insert(.whisperCLI)
        }

        if resolvedModelPath.isEmpty {
            missing.insert(.model)
        }

        if !missing.contains(.model), accelerationMode == .gpuAndANE {
            let modelURL = URL(fileURLWithPath: resolvedModelPath)
            let coreMLURL = OutputPaths.coreMLModelURL(for: modelURL)
            if !FileManager.default.fileExists(atPath: coreMLURL.path) {
                missing.insert(.coreMLEncoder)
            }
        }

        return missing
    }

    private func store(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    private var resolvedWhisperCLIPath: String {
        PathResolver.resolveWhisperCLIPath(whisperCLIPath)
    }

    private var resolvedModelPath: String {
        PathResolver.resolveModelPath(modelPath, whisperCLIPath: resolvedWhisperCLIPath)
    }

    private func resolvedOutputDirectoryPath(for inputURL: URL?, overridePath: String? = nil) -> String {
        let trimmed = (overridePath ?? outputDirectoryPath).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return PathResolver.expandingTilde(trimmed)
        }
        if let inputURL {
            return inputURL.deletingLastPathComponent().path
        }
        return ""
    }
}

private struct AppConfigurationSnapshot {
    let inputFiles: [URL]
    let outputDirectoryPath: String
    let whisperCLIPath: String
    let modelPath: String
    let accelerationMode: AccelerationMode
    let outputFormats: Set<OutputFormat>
    let sourceLanguage: String
    let translatesToEnglish: Bool
}

private enum Keys {
    static let appLanguage = "appLanguage"
    static let outputDirectoryPath = "outputDirectoryPath"
    static let whisperCLIPath = "whisperCLIPath"
    static let modelPath = "modelPath"
    static let accelerationMode = "accelerationMode"
    static let outputFormats = "outputFormats"
    static let sourceLanguage = "sourceLanguage"
    static let translatesToEnglish = "translatesToEnglish"
}
