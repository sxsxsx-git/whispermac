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
            "默认模型已设为 large-v3-turbo。",
            "音频预处理已切换为 macOS 自带的 afconvert，不再依赖第三方 ffmpeg。",
            "如果同目录存在 large-v3-turbo-encoder.mlmodelc，whisper.cpp 会自动切到 Core ML encoder。",
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
            return "\(firstInput.deletingLastPathComponent().path) (跟随输入文件)"
        }
        return "默认跟随输入文件目录"
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
            return "模型文件还不存在。先运行 `scripts/prepare-model.sh`，或者手动选择 `ggml-large-v3-turbo.bin`。"
        }
        if accelerationMode == .gpuAndANE && hasCoreML {
            return "当前模式是 GPU + ANE：encoder 会走 Core ML / ANE，decoder 继续走 Metal GPU。"
        }
        if accelerationMode == .gpuAndANE && !hasCoreML {
            return "你选择了 GPU + ANE，但还没找到 Core ML encoder；运行时会自动回退为纯 GPU。"
        }
        if hasCoreML {
            return "当前模式是纯 GPU：Core ML encoder 已存在，但运行时会被显式绕开。"
        }
        return "当前模式是纯 GPU：Whisper 只会使用 Metal GPU 路径。"
    }

    var accelerationDetail: String {
        switch accelerationMode {
        case .pureGPU:
            return "适合验证纯 Metal 路径。CPU 仍会参与音频预处理、mel 特征、调度和文本解码。"
        case .gpuAndANE:
            return "这是 Apple Silicon 上当前更完整的 offload 方式，但 decoder 和部分前后处理仍会留在 CPU / GPU。"
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
        statusText = "准备开始…"
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
            statusText = "准备失败"
            isRunning = false
            return
        }

        appendLog("准备开始，共 \(snapshot.inputFiles.count) 个文件。")
        appendLog("请求加速模式: \(snapshot.accelerationMode.title)")
        appendLog("实际加速模式: \(modelPlan.effectiveMode.title)")
        appendLog("模型路径: \(modelPlan.originalModelPath)")
        if modelPlan.executionModelPath != modelPlan.originalModelPath {
            appendLog("运行时模型路径: \(modelPlan.executionModelPath)")
        }
        appendLog("Core ML encoder: \(modelPlan.coreMLAvailable ? modelPlan.coreMLModelPath : "未找到")")
        for note in modelPlan.notes {
            appendLog(note)
        }
        if snapshot.outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendLog("输出目录: 跟随每个输入文件所在目录")
        } else {
            appendLog("输出目录: \(PathResolver.expandingTilde(snapshot.outputDirectoryPath))")
        }
        appendLog("输出格式: \(snapshot.outputFormats.map(\.rawValue).sorted().joined(separator: ", "))")

        for (index, inputURL) in snapshot.inputFiles.enumerated() {
            statusText = "处理中 \(index + 1)/\(snapshot.inputFiles.count)"
            currentFileName = inputURL.lastPathComponent
            currentFileProgress = 0
            currentStageDescription = "准备中"
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
                                self.currentStageDescription = "准备中"
                                self.currentFileProgress = 0.03
                            case .extractingAudio:
                                self.currentStageDescription = "提取音频"
                                self.currentFileProgress = max(self.currentFileProgress, 0.12)
                            case .transcribing:
                                self.currentStageDescription = self.currentTranscriptionProgress > 0
                                    ? "Whisper 转写 \(Int(self.currentTranscriptionProgress * 100))%"
                                    : "Whisper 转写"
                                self.currentFileProgress = max(self.currentFileProgress, 0.18)
                            case .finished:
                                self.currentStageDescription = "已完成"
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
                            self.currentStageDescription = "Whisper 转写 \(Int(progress * 100))%"
                            self.currentFileProgress = max(0.18, 0.18 + 0.82 * progress)
                            let completedFiles = Double(index)
                            let totalFiles = Double(snapshot.inputFiles.count)
                            self.overallProgress = min((completedFiles + self.currentFileProgress) / totalFiles, 1.0)
                        }
                    }
                )

                successCount += 1
                appendLog("完成: \(inputURL.lastPathComponent)")
                appendLog("输出目录: \(resolvedOutputDirectory.path)")
                appendLog("音频预处理: \(report.audioPreparationCommand)")
                appendLog("whisper-cli: \(report.whisperCommand)")

                if !report.outputFiles.isEmpty {
                    appendLog("生成文件:")
                    for outputFile in report.outputFiles {
                        appendLog("  \(outputFile.path)")
                    }
                }
            } catch {
                failureCount += 1
                currentFileProgress = 1
                currentStageDescription = "失败"
                appendLog("失败: \(inputURL.lastPathComponent)")
                appendLog(error.localizedDescription)
            }

            overallProgress = Double(index + 1) / Double(snapshot.inputFiles.count)
            appendLog(String(repeating: "-", count: 72))
        }

        statusText = "完成：成功 \(successCount)，失败 \(failureCount)"
        currentStageDescription = failureCount == 0 ? "全部完成" : "处理结束"
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
