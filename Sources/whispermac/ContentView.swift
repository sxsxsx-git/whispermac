import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false
    @State private var isClearHistoryConfirmationPresented = false

    private let contentMaxWidth: CGFloat = 1080
    private let fieldLabelWidth: CGFloat = 108

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                fileSection
                outputSection
                toolSection
                actionSection
                if model.isRunning {
                    liveTranscriptSection
                }
                if !model.previewFiles.isEmpty {
                    previewSection
                }
                logSection
                if !model.historyEntries.isEmpty {
                    historySection
                }
            }
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .id(model.appLanguage)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            model.promptToDownloadMissingRuntimeIfNeeded()
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            model.addMediaURLs([url])
        }
        .alert(model.runtimeDownloadPromptTitle, isPresented: $model.isRuntimeDownloadPromptPresented) {
            Button(L.tr("button.download_runtime")) {
                model.startRuntimeDownload()
            }
            Button(L.tr("button.not_now"), role: .cancel) {
                model.dismissRuntimeDownloadPrompt()
            }
        } message: {
            Text(model.runtimeDownloadPromptMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("WhisperMac")
                    .font(.system(size: 30, weight: .bold))
                Text(L.tr("app.subtitle"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Text(L.tr("label.interface_language"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            model.appLanguage = language
                        } label: {
                            if model.appLanguage == language {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(model.appLanguage.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .frame(width: 150, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button(L.tr("button.view_readme")) {
                        model.openProjectREADME()
                    }

                    Button(L.tr("button.star_on_github")) {
                        model.openProjectRepository()
                    }
                }
            }
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
                    .disabled(model.inputFiles.isEmpty || model.isBusy)
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
                            .disabled(model.isBusy)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 160, maxHeight: 200)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? Color.accentColor : .clear, lineWidth: isDropTargeted ? 3 : 0)
                .padding(2)
        )
        .dropDestination(for: URL.self) { urls, _ in
            model.addMediaURLs(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var outputSection: some View {
        GroupBox(L.tr("section.output")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L.tr("label.output_directory"))
                        .frame(width: fieldLabelWidth, alignment: .leading)
                    TextField(L.tr("placeholder.output_directory"), text: $model.outputDirectoryPath)
                        .textFieldStyle(.roundedBorder)
                    Button(L.tr("button.choose")) {
                        model.chooseOutputDirectory()
                    }
                    .disabled(model.isBusy)
                }

                Text(model.outputDirectoryDisplayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, fieldLabelWidth)

                HStack(alignment: .center, spacing: 14) {
                    Text(L.tr("label.export_formats"))
                        .frame(width: fieldLabelWidth, alignment: .leading)

                    Toggle(L.tr("toggle.export_txt"), isOn: outputBinding(for: .txt))
                    Toggle(L.tr("toggle.export_srt"), isOn: outputBinding(for: .srt))
                    Toggle(L.tr("toggle.export_vtt"), isOn: outputBinding(for: .vtt))
                    Toggle(L.tr("toggle.export_json"), isOn: outputBinding(for: .json))

                    Spacer(minLength: 8)

                    Button(L.tr("button.open_output_directory")) {
                        model.openOutputDirectory()
                    }
                    .disabled(model.inputFiles.isEmpty && model.outputDirectoryPath.isEmpty)
                    .fixedSize()
                }
            }
        }
    }

    private var toolSection: some View {
        GroupBox(L.tr("section.runtime")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Picker(L.tr("label.acceleration_mode"), selection: $model.accelerationMode) {
                        ForEach(AccelerationMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isBusy)
                    .frame(maxWidth: 320, alignment: .leading)

                    Spacer()
                }

                Text(model.accelerationDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 14) {
                    Text(L.tr("label.audio_language"))
                        .frame(width: fieldLabelWidth, alignment: .leading)

                    Picker(L.tr("label.audio_language"), selection: $model.sourceLanguage) {
                        Text(WhisperLanguage.auto.displayName).tag(WhisperLanguage.autoCode)
                        ForEach(WhisperLanguage.common) { language in
                            Text(language.displayName).tag(language.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 150, alignment: .leading)
                    .disabled(model.isBusy)

                    Toggle(L.tr("toggle.translate_to_english"), isOn: $model.translatesToEnglish)
                        .disabled(model.isBusy)

                    Spacer()
                }

                Text(L.tr("hint.translate_to_english"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, fieldLabelWidth)
                    .fixedSize(horizontal: false, vertical: true)

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

                if !model.configurationLooksReady || model.isDownloadingRuntime {
                    HStack(spacing: 12) {
                        if model.isDownloadingRuntime {
                            if let progress = model.downloadProgress {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 260)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(model.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(L.tr("button.cancel_download"), role: .destructive) {
                                model.cancelRuntimeDownload()
                            }
                        } else if !model.downloadableRuntimeComponents.isEmpty {
                            Button(L.tr("button.download_runtime")) {
                                model.promptToDownloadMissingRuntime(force: true)
                            }
                        } else {
                            Text(L.tr("hint.whisper_cli_manual"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
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

                if model.isRunning {
                    Button(L.tr("button.stop"), role: .destructive) {
                        model.cancelTranscription()
                    }
                    .disabled(model.isCancelling)
                }

                if !model.statusText.isEmpty {
                    Text(model.statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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

    private var liveTranscriptSection: some View {
        GroupBox(L.tr("section.live_transcript")) {
            VStack(alignment: .leading, spacing: 10) {
                if model.liveSegments.isEmpty {
                    Text(L.tr("live.waiting"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(model.liveSegments) { segment in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(segment.displayTimestamp)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 64, alignment: .leading)
                                        Text(segment.text)
                                            .font(.callout)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .id(segment.id)
                                }
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
                        .onChange(of: model.liveSegments.last?.id) { _, latestID in
                            guard let latestID else { return }
                            proxy.scrollTo(latestID, anchor: .bottom)
                        }
                    }
                }

                Text(L.tr("live.segment_count", model.liveSegments.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewSection: some View {
        GroupBox(L.tr("section.preview")) {
            VStack(alignment: .leading, spacing: 10) {
                if model.previewFiles.count > 1 {
                    Picker(L.tr("section.preview"), selection: previewSelection) {
                        ForEach(model.previewFiles) { file in
                            Text(file.displayName).tag(Optional(file.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320, alignment: .leading)
                }

                if model.isLoadingPreview {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                } else if model.previewSegments.isEmpty {
                    Text(L.tr("preview.unavailable"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.previewSegments) { segment in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(segment.displayTimestamp)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 64, alignment: .leading)
                                    Text(segment.text)
                                        .font(.callout)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
    }

    private var previewSelection: Binding<URL?> {
        Binding(
            get: { model.selectedPreviewFileID },
            set: { model.selectPreviewFile(id: $0) }
        )
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
            .frame(minHeight: 160, maxHeight: 220)
        }
    }

    private var historySection: some View {
        GroupBox(L.tr("section.history")) {
            VStack(alignment: .leading, spacing: 10) {
                List(model.historyEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.inputFileName)
                            Text(entry.completedAt.formatted(.dateTime.month().day().hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L.tr("button.reveal_in_finder")) {
                            model.revealHistoryEntryInFinder(entry)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
                .frame(minHeight: 80, maxHeight: 200)

                HStack {
                    Spacer()
                    Button(L.tr("button.clear_history"), role: .destructive) {
                        isClearHistoryConfirmationPresented = true
                    }
                }
            }
            .confirmationDialog(
                L.tr("alert.clear_history_title"),
                isPresented: $isClearHistoryConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(L.tr("button.clear_history_confirm"), role: .destructive) {
                    model.clearHistory()
                }
                Button(L.tr("button.not_now"), role: .cancel) {}
            }
        }
    }

    private func toolPathRow(title: String, text: Binding<String>, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .frame(width: fieldLabelWidth, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
            Button(L.tr("button.choose"), action: action)
                .disabled(model.isBusy)
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

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    ContentView()
        .environmentObject(AppModel())
}
#endif
