import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var inputFiles: [URL]
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
    @Published var logs: [String]
    @Published var isRunning = false
    @Published var statusText = ""
    @Published var overallProgress = 0.0
    @Published var currentFileProgress = 0.0
    @Published var currentFileName = ""
    @Published var currentStageDescription = ""
    @Published var currentTranscriptionProgress = 0.0

    private let defaults = UserDefaults.standard

    init() {
        let defaults = UserDefaults.standard
        let guessed = PathResolver.guessDefaults()
        let storedFormats = defaults.array(forKey: Keys.outputFormats) as? [String]
        let storedAccelerationMode = defaults.string(forKey: Keys.accelerationMode)
        var selectedFormats = Set((storedFormats ?? []).compactMap(OutputFormat.init(rawValue:)))
        if selectedFormats.isEmpty {
            selectedFormats = [.txt, .srt]
        }

        inputFiles = []
        outputDirectoryPath = defaults.string(forKey: Keys.outputDirectoryPath) ?? ""
        whisperCLIPath = defaults.string(forKey: Keys.whisperCLIPath) ?? guessed.whisperCLIPath
        modelPath = defaults.string(forKey: Keys.modelPath) ?? guessed.modelPath
        accelerationMode = AccelerationMode(rawValue: storedAccelerationMode ?? "") ?? .gpuAndANE
        outputFormats = selectedFormats

        logs = [
            L.tr("log.default_model"),
            L.tr("log.audio_preprocessor_switched"),
            L.tr("log.coreml_auto"),
        ]
    }

    var logsText: String {
        logs.joined(separator: "\n")
    }

    var canStart: Bool {
        !isRunning &&
        !inputFiles.isEmpty &&
        !whisperCLIPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !modelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !outputFormats.isEmpty
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
        FileManager.default.fileExists(atPath: PathResolver.expandingTilde(modelPath)) &&
        !PathResolver.resolveExecutablePath(whisperCLIPath).isEmpty
    }

    var accelerationSummary: String {
        let modelURL = URL(fileURLWithPath: PathResolver.expandingTilde(modelPath))
        let coreMLURL = OutputPaths.coreMLModelURL(for: modelURL)
        let hasModel = FileManager.default.fileExists(atPath: modelURL.path)
        let hasCoreML = FileManager.default.fileExists(atPath: coreMLURL.path)

        if !hasModel {
            return L.tr("summary.model_missing")
        }
        if accelerationMode == .gpuAndANE && hasCoreML {
            return L.tr("summary.mode_gpu_ane")
        }
        if accelerationMode == .gpuAndANE && !hasCoreML {
            return L.tr("summary.mode_gpu_ane_fallback")
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
        let additions = panel.urls.filter { PanelHelper.supportsFile($0) }

        for url in additions where !inputFiles.contains(url) {
            inputFiles.append(url)
        }

        if !additions.isEmpty && outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        guard canStart else { return }

        let snapshot = AppConfigurationSnapshot(
            inputFiles: inputFiles,
            outputDirectoryPath: outputDirectoryPath,
            whisperCLIPath: whisperCLIPath,
            modelPath: modelPath,
            accelerationMode: accelerationMode,
            outputFormats: outputFormats
        )

        Task {
            await runTranscription(snapshot)
        }
    }

    private func runTranscription(_ snapshot: AppConfigurationSnapshot) async {
        isRunning = true
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

        do {
            modelPlan = try RuntimeModelResolver.prepare(
                modelPath: snapshot.modelPath,
                requestedMode: snapshot.accelerationMode
            )
        } catch {
            appendLog(error.localizedDescription)
            statusText = L.tr("status.prepare_failed")
            isRunning = false
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

        for (index, inputURL) in snapshot.inputFiles.enumerated() {
            statusText = L.tr("status.processing", index + 1, snapshot.inputFiles.count)
            currentFileName = inputURL.lastPathComponent
            currentFileProgress = 0
            currentStageDescription = TranscriptionStage.preparing.description
            currentTranscriptionProgress = 0
            let resolvedOutputDirectory = URL(fileURLWithPath: resolvedOutputDirectoryPath(for: inputURL, overridePath: snapshot.outputDirectoryPath))

            do {
                let report = try await service.transcribe(
                    inputURL: inputURL,
                    outputDirectory: resolvedOutputDirectory,
                    whisperCLIPath: snapshot.whisperCLIPath,
                    modelPath: modelPlan.executionModelPath,
                    formats: snapshot.outputFormats,
                    onStageChange: { [weak self] stage in
                        await MainActor.run {
                            guard let self else { return }
                            switch stage {
                            case .preparing:
                                self.currentStageDescription = stage.description
                                self.currentFileProgress = 0.03
                            case .extractingAudio:
                                self.currentStageDescription = stage.description
                                self.currentFileProgress = max(self.currentFileProgress, 0.12)
                            case .transcribing:
                                self.currentStageDescription = self.currentTranscriptionProgress > 0
                                    ? L.tr("stage.transcribing_progress", Int(self.currentTranscriptionProgress * 100))
                                    : stage.description
                                self.currentFileProgress = max(self.currentFileProgress, 0.18)
                            case .finished:
                                self.currentStageDescription = stage.description
                                self.currentTranscriptionProgress = 1
                                self.currentFileProgress = 1
                            }
                            let completedFiles = Double(index)
                            let totalFiles = Double(snapshot.inputFiles.count)
                            self.overallProgress = min((completedFiles + self.currentFileProgress) / totalFiles, 1.0)
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
                            let completedFiles = Double(index)
                            let totalFiles = Double(snapshot.inputFiles.count)
                            self.overallProgress = min((completedFiles + self.currentFileProgress) / totalFiles, 1.0)
                        }
                    }
                )

                successCount += 1
                appendLog(L.tr("log.completed_file", inputURL.lastPathComponent))
                appendLog(L.tr("log.output_directory", resolvedOutputDirectory.path))
                appendLog(L.tr("log.audio_preparation_command", report.audioPreparationCommand))
                appendLog(L.tr("log.whisper_command", report.whisperCommand))

                if !report.outputFiles.isEmpty {
                    appendLog(L.tr("log.generated_files"))
                    for outputFile in report.outputFiles {
                        appendLog("  \(outputFile.path)")
                    }
                }
            } catch {
                failureCount += 1
                currentFileProgress = 1
                currentStageDescription = L.tr("stage.failed")
                appendLog(L.tr("log.failed_file", inputURL.lastPathComponent))
                appendLog(error.localizedDescription)
            }

            overallProgress = Double(index + 1) / Double(snapshot.inputFiles.count)
            appendLog(String(repeating: "-", count: 72))
        }

        statusText = L.tr("log.completed_summary", successCount, failureCount)
        currentStageDescription = failureCount == 0 ? L.tr("stage.all_done") : L.tr("stage.processing_finished")
        currentFileProgress = snapshot.inputFiles.isEmpty ? 0 : 1
        overallProgress = snapshot.inputFiles.isEmpty ? 0 : 1
        isRunning = false
    }

    private func appendLog(_ line: String) {
        logs.append(line)
    }

    private func store(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
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
}

private enum Keys {
    static let outputDirectoryPath = "outputDirectoryPath"
    static let whisperCLIPath = "whisperCLIPath"
    static let modelPath = "modelPath"
    static let accelerationMode = "accelerationMode"
    static let outputFormats = "outputFormats"
}
