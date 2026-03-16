import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            fileSection
            outputSection
            toolSection
            actionSection
            logSection
        }
        .padding(24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WhisperMac")
                .font(.system(size: 30, weight: .bold))
            Text("把 MP4 / M4A 转成 TXT / SRT，默认对接 `large-v3-turbo`，Whisper.cpp 用 Metal 跑 GPU，检测到 Core ML encoder 时自动启用 ANE。")
                .foregroundStyle(.secondary)
        }
    }

    private var fileSection: some View {
        GroupBox("输入文件") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("添加 MP4 / M4A") {
                        model.chooseInputFiles()
                    }
                    Button("清空列表") {
                        model.clearInputFiles()
                    }
                    .disabled(model.inputFiles.isEmpty || model.isRunning)
                    Spacer()
                    Text("\(model.inputFiles.count) 个文件")
                        .foregroundStyle(.secondary)
                }

                if model.inputFiles.isEmpty {
                    Text("还没有选择文件。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    List(model.inputFiles, id: \.path) { url in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                Text(url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("移除") {
                                model.removeInputFile(url)
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.isRunning)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 160, maxHeight: 200)
                }
            }
        }
    }

    private var outputSection: some View {
        GroupBox("输出") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("输出目录")
                        .frame(width: 90, alignment: .leading)
                    TextField("留空时跟随输入文件目录", text: $model.outputDirectoryPath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") {
                        model.chooseOutputDirectory()
                    }
                    .disabled(model.isRunning)
                }

                Text(model.outputDirectoryDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    Toggle("导出 TXT", isOn: outputBinding(for: .txt))
                    Toggle("导出 SRT", isOn: outputBinding(for: .srt))
                    Spacer()
                    Button("打开输出目录") {
                        model.openOutputDirectory()
                    }
                    .disabled(model.inputFiles.isEmpty && model.outputDirectoryPath.isEmpty)
                }
            }
        }
    }

    private var toolSection: some View {
        GroupBox("运行环境") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("加速模式")
                    Picker("加速模式", selection: $model.accelerationMode) {
                        ForEach(AccelerationMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isRunning)

                    Text(model.accelerationDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                toolPathRow(title: "whisper-cli", text: $model.whisperCLIPath) {
                    model.chooseWhisperCLI()
                }
                toolPathRow(title: "模型文件", text: $model.modelPath) {
                    model.chooseModel()
                }

                Text("音频预处理使用系统自带的 afconvert，不需要额外安装 ffmpeg。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(model.accelerationSummary)
                    .font(.callout)
                    .foregroundStyle(model.configurationLooksReady ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Button(model.isRunning ? "转写中…" : "开始转写") {
                    model.startTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)

                if !model.statusText.isEmpty {
                    Text(model.statusText)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("查看 README") {
                    model.openProjectREADME()
                }
            }

            if model.isRunning || model.overallProgress > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: model.overallProgress) {
                        Text("总进度")
                    } currentValueLabel: {
                        Text("\(Int(model.overallProgress * 100))%")
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: model.currentFileProgress) {
                        Text(model.currentFileName.isEmpty ? "当前文件" : model.currentFileName)
                    } currentValueLabel: {
                        Text(model.currentStageDescription.isEmpty ? "\(Int(model.currentFileProgress * 100))%" : model.currentStageDescription)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var logSection: some View {
        GroupBox("日志") {
            ScrollView {
                Text(model.logsText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 220)
        }
    }

    private func toolPathRow(title: String, text: Binding<String>, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .frame(width: 90, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
            Button("选择…", action: action)
                .disabled(model.isRunning)
        }
    }

    private func outputBinding(for format: OutputFormat) -> Binding<Bool> {
        Binding(
            get: { model.outputFormats.contains(format) },
            set: { enabled in
                model.setFormat(format, enabled: enabled)
            }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
