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
            Text(L.tr("app.subtitle"))
                .foregroundStyle(.secondary)
        }
    }

    private var fileSection: some View {
        GroupBox(L.tr("section.input_files")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(L.tr("button.add_media")) {
                        model.chooseInputFiles()
                    }
                    Button(L.tr("button.clear_list")) {
                        model.clearInputFiles()
                    }
                    .disabled(model.inputFiles.isEmpty || model.isRunning)
                    Spacer()
                    Text(L.tr("label.file_count", model.inputFiles.count))
                        .foregroundStyle(.secondary)
                }

                if model.inputFiles.isEmpty {
                    Text(L.tr("message.no_files_selected"))
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
                            Button(L.tr("button.remove")) {
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
        GroupBox(L.tr("section.output")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L.tr("label.output_directory"))
                        .frame(width: 90, alignment: .leading)
                    TextField(L.tr("placeholder.output_directory"), text: $model.outputDirectoryPath)
                        .textFieldStyle(.roundedBorder)
                    Button(L.tr("button.choose")) {
                        model.chooseOutputDirectory()
                    }
                    .disabled(model.isRunning)
                }

                Text(model.outputDirectoryDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    Toggle(L.tr("toggle.export_txt"), isOn: outputBinding(for: .txt))
                    Toggle(L.tr("toggle.export_srt"), isOn: outputBinding(for: .srt))
                    Spacer()
                    Button(L.tr("button.open_output_directory")) {
                        model.openOutputDirectory()
                    }
                    .disabled(model.inputFiles.isEmpty && model.outputDirectoryPath.isEmpty)
                }
            }
        }
    }

    private var toolSection: some View {
        GroupBox(L.tr("section.runtime")) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.tr("label.acceleration_mode"))
                    Picker(L.tr("label.acceleration_mode"), selection: $model.accelerationMode) {
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

                toolPathRow(title: L.tr("field.whisper_cli"), text: $model.whisperCLIPath) {
                    model.chooseWhisperCLI()
                }
                toolPathRow(title: L.tr("field.model_file"), text: $model.modelPath) {
                    model.chooseModel()
                }

                Text(L.tr("hint.audio_preprocessor"))
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
                Button(model.isRunning ? L.tr("button.transcribing") : L.tr("button.start_transcription")) {
                    model.startTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)

                if !model.statusText.isEmpty {
                    Text(model.statusText)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L.tr("button.view_readme")) {
                    model.openProjectREADME()
                }

                Button(L.tr("button.star_on_github")) {
                    model.openProjectRepository()
                }
            }

            if model.isRunning || model.overallProgress > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: model.overallProgress) {
                        Text(L.tr("label.overall_progress"))
                    } currentValueLabel: {
                        Text("\(Int(model.overallProgress * 100))%")
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: model.currentFileProgress) {
                        Text(model.currentFileName.isEmpty ? L.tr("label.current_file") : model.currentFileName)
                    } currentValueLabel: {
                        Text(model.currentStageDescription.isEmpty ? "\(Int(model.currentFileProgress * 100))%" : model.currentStageDescription)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var logSection: some View {
        GroupBox(L.tr("section.logs")) {
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
            Button(L.tr("button.choose"), action: action)
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
