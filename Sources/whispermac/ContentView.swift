import SwiftUI

/// P0.2 window skeleton: fixed 236 pt task queue on the left, a state-driven
/// main workspace on the right, and a persistent 80 pt action bar at the
/// bottom. Toolbar carries add-media / history / settings; logs, history, and
/// outputs open as sheets on demand.
struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTargeted = false
    @State private var presentedSheet: PresentedSheet?
    @State private var isClearHistoryConfirmationPresented = false

    enum PresentedSheet: String, Identifiable {
        case settings
        case history
        case logs
        case allOutputs

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TaskQueueView()
                Divider()
                mainWorkspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color.accentColor.opacity(0.06))
                            RoundedRectangle(cornerRadius: 0)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
            }
            PersistentActionBar(
                openLogs: { presentedSheet = .logs },
                openSettings: { presentedSheet = .settings }
            )
        }
        .id(model.appLanguage)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { toolbarContent }
        .sheet(item: $presentedSheet) { sheet in
            presentedSheetView(sheet)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.isRunning else { return false }
            model.addMediaURLs(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted && !model.isRunning
        }
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

    // MARK: workspace switch

    @ViewBuilder private var mainWorkspace: some View {
        switch model.mainContentState {
        case let .running(phase):
            RunWorkspaceView(phase: phase)
        case .downloadingRuntime:
            DownloadWorkspaceView()
        case let .finished(outcome):
            RunResultView(
                outcome: outcome,
                openLogs: { presentedSheet = .logs },
                openAllOutputs: { presentedSheet = .allOutputs }
            )
        case let .setup(readiness):
            SetupWorkspaceView(
                readiness: readiness,
                openSettings: { presentedSheet = .settings }
            )
        }
    }

    // MARK: toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.chooseInputFiles()
            } label: {
                Label(L.tr("button.add_media"), systemImage: "plus")
            }
            .disabled(model.isRunning)
            .keyboardShortcut("o")
            .accessibilityHint(Text(model.isRunning ? L.tr("queue.locked") : L.tr("empty.drop.detail")))

            Button {
                presentedSheet = .history
            } label: {
                Label(L.tr("button.history"), systemImage: "clock.arrow.circlepath")
            }

            Button {
                presentedSheet = .settings
            } label: {
                Label(L.tr("button.settings"), systemImage: "gearshape")
            }
        }
    }

    // MARK: sheets

    @ViewBuilder private func presentedSheetView(_ sheet: PresentedSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsSheet()
        case .history:
            HistorySheet(isClearConfirmationPresented: $isClearHistoryConfirmationPresented)
        case .logs:
            LogsSheet()
        case .allOutputs:
            AllOutputsSheet()
        }
    }
}

// MARK: - Task queue (left column)

struct TaskQueueView: View {
    @EnvironmentObject private var model: AppModel

    private var isLocked: Bool { model.isRunning }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.tr("queue.title"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(L.tr("label.file_count", model.inputFiles.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if model.inputFiles.isEmpty {
                VStack(spacing: 6) {
                    Text(L.tr("queue.empty.title"))
                        .font(.system(size: 13))
                    Text(L.tr("queue.empty.detail"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(model.inputFiles, id: \.path) { url in
                    queueRow(url)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }

            Divider()
            footer
        }
        .frame(width: TaskWorkspaceMetrics.queueWidth)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(L.tr("queue.title")))
    }

    private func queueRow(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForExtension(url.pathExtension))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if !isLocked {
                Button {
                    model.removeInputFile(url)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L.tr("button.remove"))
                .accessibilityValue(Text(url.lastPathComponent))
            }
        }
        .padding(.vertical, 8)
        .help(url.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(url.lastPathComponent), \(url.deletingLastPathComponent().path)"))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if isLocked {
                Image(systemName: "lock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(L.tr("queue.locked"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(L.tr("privacy.local"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer()
            Button(L.tr("button.clear_list")) {
                model.clearInputFiles()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(model.inputFiles.isEmpty || model.isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func iconForExtension(_ pathExtension: String) -> String {
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
        return videoExtensions.contains(pathExtension.lowercased()) ? "film" : "music.note"
    }
}

// MARK: - Persistent action bar (bottom)

struct PersistentActionBar: View {
    @EnvironmentObject private var model: AppModel
    let openLogs: () -> Void
    let openSettings: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var barHeight: CGFloat {
        dynamicTypeSize >= .xLarge ? 96 : 80
    }

    var body: some View {
        HStack(spacing: 16) {
            leading
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: barHeight, maxHeight: barHeight, alignment: .center)
        .background {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                Spacer()
            }
        }
    }

    // MARK: leading status

    @ViewBuilder private var leading: some View {
        switch model.mainContentState {
        case let .running(phase):
            runningLeading(phase)
        case .downloadingRuntime:
            downloadLeading
        case let .finished(outcome):
            switch outcome {
            case let .succeeded(inputFileCount, _):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Text(L.tr("bar.done_files", inputFileCount))
                        .font(.system(size: 13, weight: .medium))
                }
            case let .failed(summary):
                HStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(Color(nsColor: .systemRed))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.tr("bar.failure"))
                            .font(.system(size: 13, weight: .medium))
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(summary)
                    }
                }
            case .cancelled:
                HStack(spacing: 8) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                    Text(L.tr("bar.cancelled"))
                        .font(.system(size: 13, weight: .medium))
                }
            }
        case let .setup(readiness):
            setupLeading(readiness)
        }
    }

    private func runningLeading(_ phase: ActiveRunPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stageTitle(phase))
                .font(.system(size: 13, weight: .medium))
            HStack(spacing: 10) {
                if phase == .stopping {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    ProgressView(value: model.overallProgress)
                        .frame(width: 220)
                    Text(progressCaption(phase))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(stageTitle(phase)))
    }

    private func stageTitle(_ phase: ActiveRunPhase) -> String {
        switch phase {
        case let .preparingInputs(currentIndex, total):
            let nextIndex = min(currentIndex + 1, max(total, 1))
            let fileName = model.currentFileName
            if fileName.isEmpty {
                return L.tr("status.processing", nextIndex, total)
            }
            return L.tr("bar.stage.preparing", nextIndex, total, fileName)
        case let .transcribingBatch(totalFiles):
            return L.tr("bar.stage.transcribing", totalFiles)
        case .stopping:
            return L.tr("bar.stage.stopping")
        }
    }

    /// The bar is the 18% preprocessing / 82% whisper estimate; the caption
    /// keeps the "estimated" qualifier so 100% is never read as success.
    private func progressCaption(_ phase: ActiveRunPhase) -> String {
        switch phase {
        case .preparingInputs:
            return L.tr("bar.progress.estimated_percent", Int(model.overallProgress * 100))
        case .transcribingBatch:
            return L.tr("bar.progress.estimated_percent", Int(model.currentTranscriptionProgress * 100))
        case .stopping:
            return ""
        }
    }

    private var downloadLeading: some View {
        HStack(spacing: 10) {
            if let progress = model.downloadProgress {
                ProgressView(value: progress)
                    .frame(width: 220)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.statusText)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
        }
    }

    private func setupLeading(_ readiness: SetupReadiness) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(setupStatusLine(readiness))
                .font(.system(size: 13, weight: .medium))
            Text(L.tr("privacy.local"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func setupStatusLine(_ readiness: SetupReadiness) -> String {
        if model.isDownloadingRuntime {
            return model.statusText
        }
        if let reason = model.startDisabledReason {
            return disabledReasonText(reason)
        }
        return L.tr("bar.ready_files", model.inputFiles.count)
    }

    private func disabledReasonText(_ reason: StartDisabledReason) -> String {
        switch reason {
        case .running, .downloadingRuntime:
            return model.statusText
        case .noInputFiles:
            return L.tr("bar.reason.add_media")
        case .missingWhisperCLI:
            return L.tr("bar.reason.cli")
        case .missingModel:
            return L.tr("bar.reason.model")
        case .noOutputFormats:
            return L.tr("bar.reason.formats")
        }
    }

    // MARK: trailing actions

    @ViewBuilder private var trailing: some View {
        switch model.mainContentState {
        case .running:
            runningTrailing
        case .downloadingRuntime:
            Button(L.tr("button.cancel_download"), role: .destructive) {
                model.cancelRuntimeDownload()
            }
            .buttonStyle(.bordered)
        case let .finished(outcome):
            switch outcome {
            case .succeeded:
                successTrailing
            case .failed:
                Button(L.tr("bar.view_logs"), action: openLogs)
                    .buttonStyle(.bordered)
                Button(L.tr("result.retry")) {
                    model.startTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)
            case .cancelled:
                Button(L.tr("options.adjust")) {
                    model.dismissOutcome()
                }
                .buttonStyle(.bordered)
                Button(L.tr("result.start_again")) {
                    model.startTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)
            }
        case .setup:
            setupTrailing
        }
    }

    private var runningTrailing: some View {
        HStack(spacing: 12) {
            Button(L.tr("bar.view_logs"), action: openLogs)
                .buttonStyle(.bordered)

            // Deliberately a plain destructive bordered button, never a blue
            // prominent one; it is the only destructive action of a run.
            Button(role: .destructive) {
                model.cancelTranscription()
            } label: {
                Text(L.tr("button.stop"))
            }
            .buttonStyle(.bordered)
            .disabled(model.isCancelling)
        }
    }

    private var successTrailing: some View {
        HStack(spacing: 12) {
            Button(L.tr("result.new_task")) {
                model.dismissOutcome()
            }
            .buttonStyle(.bordered)

            Button {
                model.revealSelectedResultInFinder()
            } label: {
                Label(
                    model.previewFiles.isEmpty
                        ? L.tr("result.show_selected_output")
                        : L.tr("result.show_selected_subtitle"),
                    systemImage: "folder"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(revealTargetURL == nil)
        }
    }

    private var revealTargetURL: URL? {
        model.selectedPreviewFileID ?? model.selectedResultFileID ?? model.lastRunOutputFiles.first
    }

    private var setupTrailing: some View {
        Button(L.tr("button.start_transcription")) {
            model.startTranscription()
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.startDisabledReason != nil)
        .accessibilityValue(Text(setupAccessibilityValue))
    }

    private var setupAccessibilityValue: String {
        if let reason = model.startDisabledReason {
            return disabledReasonText(reason)
        }
        return L.tr("bar.ready_files", model.inputFiles.count)
    }
}

// MARK: - Settings sheet

struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L.tr("button.settings"))
                .font(.system(size: 22, weight: .semibold))

            GroupBox(L.tr("settings.section.general")) {
                HStack {
                    Text(L.tr("label.interface_language"))
                        .frame(width: 104, alignment: .leading)
                    Picker(L.tr("label.interface_language"), selection: $model.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200, alignment: .leading)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            GroupBox(L.tr("settings.section.paths")) {
                VStack(spacing: 12) {
                    pathRow(title: L.tr("field.whisper_cli"), text: $model.whisperCLIPath) {
                        model.chooseWhisperCLI()
                    }
                    pathRow(title: L.tr("field.model_file"), text: $model.modelPath) {
                        model.chooseModel()
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox(L.tr("section.runtime")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(L.tr("label.acceleration_mode"), selection: $model.accelerationMode) {
                        ForEach(AccelerationMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280, alignment: .leading)
                    .disabled(model.isBusy)

                    Text(model.accelerationDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.accelerationSummary)
                        .font(.callout)
                        .foregroundStyle(
                            model.configurationLooksReady
                                ? AnyShapeStyle(.secondary)
                                : AnyShapeStyle(Color(nsColor: .systemOrange))
                        )
                        .fixedSize(horizontal: false, vertical: true)

                    downloadStatusRow
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack(spacing: 12) {
                Text(L.tr("settings.section.help"))
                    .font(.headline)
                Button(L.tr("button.view_readme")) {
                    model.openProjectREADME()
                }
                Button(L.tr("button.star_on_github")) {
                    model.openProjectRepository()
                }
                Spacer()
                Button(L.tr("button.done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, alignment: .topLeading)
    }

    @ViewBuilder private var downloadStatusRow: some View {
        if model.isDownloadingRuntime {
            HStack(spacing: 12) {
                if let progress = model.downloadProgress {
                    ProgressView(value: progress)
                        .frame(width: 200)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button(L.tr("button.cancel_download"), role: .destructive) {
                    model.cancelRuntimeDownload()
                }
            }
        } else if !model.downloadableRuntimeComponents.isEmpty {
            HStack(spacing: 12) {
                Button(L.tr("button.download_runtime")) {
                    model.startRuntimeDownload()
                }
                Text(L.tr("privacy.download"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pathRow(title: String, text: Binding<String>, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .frame(width: 104, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
            Button(L.tr("button.choose"), action: choose)
                .disabled(model.isBusy)
        }
    }
}

// MARK: - History sheet

struct HistorySheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var isClearConfirmationPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(L.tr("section.history"))
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            if model.historyEntries.isEmpty {
                Text(L.tr("history.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
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
            }

            Divider()
            HStack {
                Spacer()
                Button(L.tr("button.clear_history"), role: .destructive) {
                    isClearConfirmationPresented = true
                }
                .disabled(model.historyEntries.isEmpty)
                Button(L.tr("button.done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: 440)
        .confirmationDialog(
            L.tr("alert.clear_history_title"),
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(L.tr("button.clear_history_confirm"), role: .destructive) {
                model.clearHistory()
            }
            Button(L.tr("button.not_now"), role: .cancel) {}
        }
    }
}

// MARK: - Logs sheet

struct LogsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(L.tr("section.logs"))
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                Text(model.logsText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button(L.tr("button.done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 680, height: 500)
    }
}

// MARK: - All outputs sheet

struct AllOutputsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(L.tr("sheet.all_outputs.title"))
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            if model.lastRunOutputFiles.isEmpty {
                Text(L.tr("sheet.all_outputs.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List(model.lastRunOutputFiles, id: \.self) { url in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(url.pathExtension.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        Button(L.tr("button.reveal_in_finder")) {
                            model.revealOutputFileInFinder(url)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }

            Divider()
            HStack {
                Spacer()
                Button(L.tr("button.done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 440)
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    ContentView()
        .environmentObject(AppModel())
}
#endif
