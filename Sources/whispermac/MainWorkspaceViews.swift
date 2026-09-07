import SwiftUI

// MARK: - P0.2 main workspace views
//
// The right-hand workspace swaps its contents by state; the window skeleton
// (toolbar / queue / bottom bar) stays put. Design inputs:
// docs/ui-visual-spec.zh-CN.md and docs/design/whispermac-ui-prototype.html.

enum TaskWorkspaceMetrics {
    static let queueWidth: CGFloat = 236
    static let workspaceDividerWidth: CGFloat = 1
    // Width-class thresholds measured on the workspace (window content width
    // minus queue and divider). The 40 pt gap between them is hysteresis:
    // `expanded` is entered at 1100 and only left below 1060, so a live
    // resize cannot oscillate the layout around a single value.
    static let expandWorkspaceThreshold: CGFloat = 1100
    static let collapseWorkspaceThreshold: CGFloat = 1060
    static let contentTopPadding: CGFloat = 28
    static let contentHorizontalPadding: CGFloat = 32
    static let sectionSpacing: CGFloat = 24
    static let readingColumnMaxWidth: CGFloat = 760
    static let readingColumnMaxWidthExpanded: CGFloat = 820
    static let labelColumnWidth: CGFloat = 104
}

/// Caps workspace content to a single reading column: 760 pt left-aligned in
/// the regular width class; 820 pt centered once the workspace is expanded,
/// so large windows and full screen keep symmetric breathing room instead of
/// one-sided blank space. Column content stays leading-aligned in both.
extension View {
    func readingColumn(_ mode: WindowSizeMode) -> some View {
        frame(maxWidth: mode == .expanded
            ? TaskWorkspaceMetrics.readingColumnMaxWidthExpanded
            : TaskWorkspaceMetrics.readingColumnMaxWidth,
            alignment: .leading)
            .frame(maxWidth: .infinity, alignment: mode == .expanded ? .center : .leading)
    }
}

/// DEBUG-only typography scale for layout verification (plan §6.1): launch
/// with `WHISPERMAC_UI_FONT_SCALE=1.2` to multiply every explicit point size
/// below. In release builds the value is always 1 and there is no entry point.
enum UITypographyScale {
    static let value: CGFloat = {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["WHISPERMAC_UI_FONT_SCALE"],
              let parsed = Double(raw), parsed > 0 else { return 1 }
        return CGFloat(parsed)
        #else
        return 1
        #endif
    }()

    static func scaled(_ size: CGFloat) -> CGFloat { size * value }
}

// MARK: - Shared pieces

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: UITypographyScale.scaled(15), weight: .semibold))
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

/// Label row that collapses to a vertical layout when the horizontal form no
/// longer fits (large text, CJK, narrow window). The horizontal candidate's
/// label keeps its natural width above the 104 pt baseline so an overlong
/// label is measured truthfully and the candidate is rejected, never masked.
struct LabeledRow<Content: View>: View {
    let title: String
    var secondaryTitle: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                titleText
                    .frame(minWidth: TaskWorkspaceMetrics.labelColumnWidth, alignment: .leading)
                content
            }
            VStack(alignment: .leading, spacing: 6) {
                titleText
                content
            }
        }
    }

    @ViewBuilder private var titleText: some View {
        if secondaryTitle {
            Text(title).foregroundStyle(.secondary)
        } else {
            Text(title)
        }
    }
}

struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(segment.displayTimestamp)
                .font(.system(size: UITypographyScale.scaled(12), design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(segment.text)
                .font(.system(size: UITypographyScale.scaled(14)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

func languageDisplayName(forCode code: String) -> String {
    guard code != WhisperLanguage.autoCode else {
        return WhisperLanguage.auto.displayName
    }
    return WhisperLanguage.common.first { $0.code == code }?.displayName
        ?? WhisperLanguage.auto.displayName
}

func outputLocationDisplayText(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? L.tr("options.output.follow") : trimmed
}

func formatsSummaryText(_ formats: Set<OutputFormat>) -> String {
    OutputFormat.allCases
        .filter { formats.contains($0) }
        .map { $0.rawValue.uppercased() }
        .joined(separator: " · ")
}

private var semanticSuccessColor: Color { Color(nsColor: .systemGreen) }
private var semanticWarningColor: Color { Color(nsColor: .systemOrange) }
private var semanticErrorColor: Color { Color(nsColor: .systemRed) }

/// Chooses the prominent (or plain bordered) style while keeping a single
/// prominent action per state.
private struct ProminentStyleModifier: ViewModifier {
    let isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private extension View {
    func prominent(if isPrimary: Bool) -> some View {
        modifier(ProminentStyleModifier(isPrimary: isPrimary))
    }
}

// MARK: - Setup workspace (empty queue / ready form)

struct SetupWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.windowSizeMode) private var windowSizeMode
    let readiness: SetupReadiness
    let openSettings: () -> Void
    @State private var showsFullOptions = false

    private var missingBlockers: Set<RuntimeComponent> {
        if case let .missingRuntime(blockers) = readiness {
            return blockers
        }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaskWorkspaceMetrics.sectionSpacing) {
                titleBlock

                switch readiness {
                case .emptyQueue:
                    dropInvite
                    if showsFullOptions {
                        optionsForm
                    } else {
                        defaultsSummary
                    }
                case let .missingRuntime(blockers):
                    if model.inputFiles.isEmpty {
                        if blockers.contains(.whisperCLI) {
                            MissingCLIPanel(isPrimary: true)
                        }
                        if blockers.contains(.model) {
                            MissingModelPanel(isPrimary: !blockers.contains(.whisperCLI))
                        }
                        if showsFullOptions {
                            optionsForm
                        } else {
                            defaultsSummary
                        }
                    } else {
                        optionsForm
                    }
                case .ready:
                    optionsForm
                }
            }
            .padding(.top, TaskWorkspaceMetrics.contentTopPadding)
            .padding(.horizontal, TaskWorkspaceMetrics.contentHorizontalPadding)
            .padding(.bottom, 24)
            .readingColumn(windowSizeMode)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.tr("empty.title"))
                .font(.system(size: UITypographyScale.scaled(22), weight: .semibold))
            Text(L.tr("empty.subtitle"))
                .foregroundStyle(.secondary)
        }
    }

    private var dropInvite: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: UITypographyScale.scaled(40)))
                .foregroundStyle(.secondary)
            Text(L.tr("empty.drop.title"))
                .font(.system(size: UITypographyScale.scaled(20), weight: .medium))
            Text(L.tr("empty.drop.detail"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                model.chooseInputFiles()
            } label: {
                Label(L.tr("button.add_media"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(Color(nsColor: .separatorColor))
        )
        .padding(.vertical, 4)
    }

    private var defaultsSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: L.tr("empty.defaults.title"))
                Spacer()
                Button(L.tr("options.adjust")) {
                    showsFullOptions = true
                }
                .buttonStyle(.link)
            }

            VStack(alignment: .leading, spacing: 8) {
                defaultsRow(L.tr("label.output_directory"), outputLocationDisplayText(model.outputDirectoryPath))
                defaultsRow(L.tr("label.export_formats"), formatsSummaryText(model.outputFormats))
                defaultsRow(L.tr("label.audio_language"), languageDisplayName(forCode: model.sourceLanguage))
            }
        }
    }

    private func defaultsRow(_ label: String, _ value: String) -> some View {
        LabeledRow(title: label, secondaryTitle: true) {
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: UITypographyScale.scaled(13)))
    }

    private var optionsForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: L.tr("options.section.output"))
                outputLocationRow
                formatsGrid
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: L.tr("options.section.transcribe"))
                languageRow
                translateRow
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: L.tr("section.runtime"))
                accelerationRow
            }

            Divider()

            readinessSection
        }
    }

    private var outputLocationRow: some View {
        LabeledRow(title: L.tr("label.output_directory")) {
            Menu {
                Button(L.tr("options.output.follow")) {
                    model.outputDirectoryPath = ""
                }
                if !model.outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(model.outputDirectoryPath) {}
                        .disabled(true)
                }
                Divider()
                Button(L.tr("options.output.choose")) {
                    model.chooseOutputDirectory()
                }
            } label: {
                HStack {
                    Text(outputLocationDisplayText(model.outputDirectoryPath))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 560, alignment: .leading)
            .disabled(model.isBusy)
        }
    }

    private var formatsGrid: some View {
        LabeledRow(title: L.tr("label.export_formats")) {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    formatToggle(.txt)
                    formatToggle(.srt)
                    formatToggle(.vtt)
                    formatToggle(.json)
                }
                Text(L.tr("options.formats.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatToggle(_ format: OutputFormat) -> some View {
        Toggle(L.tr("toggle.export_\(format.rawValue)"), isOn: formatBinding(for: format))
            .disabled(model.isBusy || model.outputFormats == [format])
    }

    private func formatBinding(for format: OutputFormat) -> Binding<Bool> {
        Binding(
            get: { model.outputFormats.contains(format) },
            set: { enabled in model.setFormat(format, enabled: enabled) }
        )
    }

    private var languageRow: some View {
        LabeledRow(title: L.tr("label.audio_language")) {
            Picker(L.tr("label.audio_language"), selection: $model.sourceLanguage) {
                Text(WhisperLanguage.auto.displayName).tag(WhisperLanguage.autoCode)
                ForEach(WhisperLanguage.common) { language in
                    Text(language.displayName).tag(language.code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(minWidth: 200, idealWidth: 240, maxWidth: 360, alignment: .leading)
            .disabled(model.isBusy)
        }
    }

    private var translateRow: some View {
        LabeledRow(title: L.tr("options.translate")) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(L.tr("toggle.translate_to_english"), isOn: $model.translatesToEnglish)
                    .disabled(model.isBusy)
                Text(L.tr("hint.translate_to_english"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accelerationRow: some View {
        LabeledRow(title: L.tr("label.acceleration_mode")) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.accelerationMode.title)
                        .fontWeight(.medium)
                    Text(model.accelerationSummary)
                        .font(.caption)
                        .foregroundStyle(model.configurationLooksReady ? AnyShapeStyle(.secondary) : AnyShapeStyle(semanticWarningColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L.tr("options.view_settings")) {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L.tr("ready.title"))

            if missingBlockers.isEmpty {
                if model.inputFiles.isEmpty {
                    HStack(spacing: 8) {
                        StatusDot(color: semanticWarningColor)
                        Text(L.tr("ready.add_media_first"))
                    }
                } else {
                    HStack(spacing: 8) {
                        StatusDot(color: semanticSuccessColor)
                        Text(L.tr("ready.files", model.inputFiles.count))
                            .fontWeight(.medium)
                        Text(L.tr("ready.output_note"))
                            .foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                }
            } else {
                if missingBlockers.contains(.whisperCLI) {
                    readinessWarningRow(
                        text: L.tr("missing.cli.title")
                    ) {
                        Button(L.tr("missing.choose_cli")) {
                            model.chooseWhisperCLI()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if missingBlockers.contains(.model) {
                    readinessWarningRow(
                        text: L.tr("missing.model.title")
                    ) {
                        Button(L.tr("missing.download_default_model")) {
                            model.startRuntimeDownload()
                        }
                        .buttonStyle(.bordered)
                        Button(L.tr("missing.choose_existing_model")) {
                            model.chooseModel()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func readinessWarningRow<Actions: View>(
        text: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 8) {
            StatusDot(color: semanticWarningColor)
            Text(text)
            Spacer(minLength: 12)
            actions()
        }
    }
}

// MARK: - Missing runtime panels (empty queue)

struct MissingModelPanel: View {
    @EnvironmentObject private var model: AppModel
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "square.stack.3d.down.right")
                .font(.system(size: UITypographyScale.scaled(36)))
                .foregroundStyle(.secondary)
            Text(L.tr("missing.model.title"))
                .font(.system(size: UITypographyScale.scaled(20), weight: .semibold))
            Text(L.tr("missing.model.detail"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button {
                    model.startRuntimeDownload()
                } label: {
                    Label(L.tr("missing.download_default_model"), systemImage: "arrow.down.circle")
                }
                .prominent(if: isPrimary)

                Button(L.tr("missing.choose_existing_model")) {
                    model.chooseModel()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}

struct MissingCLIPanel: View {
    @EnvironmentObject private var model: AppModel
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: UITypographyScale.scaled(36)))
                .foregroundStyle(.secondary)
            Text(L.tr("missing.cli.title"))
                .font(.system(size: UITypographyScale.scaled(20), weight: .semibold))
            Text(L.tr("hint.whisper_cli_manual"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L.tr("missing.choose_cli")) {
                model.chooseWhisperCLI()
            }
            .prominent(if: isPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}

// MARK: - Download workspace

struct DownloadWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.windowSizeMode) private var windowSizeMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaskWorkspaceMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.statusText.isEmpty ? L.tr("status.runtime_preparing_download") : model.statusText)
                        .font(.system(size: UITypographyScale.scaled(22), weight: .semibold))
                    Text(L.tr("privacy.download"))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let progress = model.downloadProgress {
                        ProgressView(value: progress)
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 420)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text(L.tr("bar.progress.estimated"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(L.tr("privacy.local"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, TaskWorkspaceMetrics.contentTopPadding)
            .padding(.horizontal, TaskWorkspaceMetrics.contentHorizontalPadding)
            .padding(.bottom, 24)
            .readingColumn(windowSizeMode)
        }
    }
}

// MARK: - Running workspace

struct RunWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.windowSizeMode) private var windowSizeMode
    let phase: ActiveRunPhase

    @State private var showsSnapshotDetail = false
    @State private var followsLatest = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Transcript viewport floor: `max(240, H − F)` per plan R4. `H` is this
    /// view's measured height; `F` is the measured height of everything that
    /// is not the viewport (title/detail block, section header, follow row,
    /// divider, paddings, spacings). Below the floor the retained page-level
    /// ScrollView absorbs the overflow instead of crushing the viewport.
    private let liveTranscriptMinHeight: CGFloat = 240
    private let liveSectionSpacing: CGFloat = 12

    @State private var workspaceHeight: CGFloat = 0
    @State private var headerBlockHeight: CGFloat = 0
    @State private var sectionHeaderHeight: CGFloat = 0
    @State private var followRowHeight: CGFloat = 0

    /// Everything around the viewport: page paddings, the page-level gap, the
    /// three live-section gaps and the divider. Each counted exactly once.
    private var viewportChromeHeight: CGFloat {
        TaskWorkspaceMetrics.contentTopPadding
            + TaskWorkspaceMetrics.sectionSpacing      // header block ↔ live section
            + 3 * liveSectionSpacing
            + 1                                        // divider
            + 24                                       // page bottom padding
    }

    private var viewportHeight: CGFloat {
        guard workspaceHeight > 0, headerBlockHeight > 0,
              sectionHeaderHeight > 0, followRowHeight > 0 else {
            return liveTranscriptMinHeight
        }
        let surrounding = viewportChromeHeight + headerBlockHeight + sectionHeaderHeight + followRowHeight
        return max(liveTranscriptMinHeight, workspaceHeight - surrounding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaskWorkspaceMetrics.sectionSpacing) {
                headerBlock
                liveTranscriptSection
            }
            .padding(.top, TaskWorkspaceMetrics.contentTopPadding)
            .padding(.horizontal, TaskWorkspaceMetrics.contentHorizontalPadding)
            .padding(.bottom, 24)
            .readingColumn(windowSizeMode)
        }
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { workspaceHeight = $0.height }
    }

    /// Title + frozen task details, measured together as the non-viewport
    /// header content; re-measures itself when the disclosure expands.
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: TaskWorkspaceMetrics.sectionSpacing) {
            titleBlock

            if let snapshot = model.activeSnapshot {
                snapshotDisclosure(snapshot)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerBlockHeight = $0 }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phaseTitle)
                .font(.system(size: UITypographyScale.scaled(22), weight: .semibold))
            if !phaseSubtitle.isEmpty {
                Text(phaseSubtitle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .preparingInputs:
            return L.tr("run.title.preparing")
        case .transcribingBatch:
            return L.tr("run.title.batch")
        case .stopping:
            return L.tr("bar.stage.stopping")
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case let .preparingInputs(currentIndex, total):
            let fileName = model.currentFileName
            if fileName.isEmpty {
                return L.tr("status.processing", min(currentIndex + 1, max(total, 1)), total)
            }
            return L.tr("bar.stage.preparing", min(currentIndex + 1, max(total, 1)), total, fileName)
        case .transcribingBatch:
            return L.tr("run.subtitle.batch")
        case .stopping:
            return L.tr("run.subtitle.batch")
        }
    }

    private func snapshotDisclosure(_ snapshot: AppConfigurationSnapshot) -> some View {
        DisclosureGroup(isExpanded: $showsSnapshotDetail) {
            VStack(alignment: .leading, spacing: 8) {
                snapshotRow(L.tr("label.output_directory"), outputLocationDisplayText(snapshot.outputDirectoryPath))
                snapshotRow(L.tr("label.audio_language"), languageDisplayName(forCode: snapshot.sourceLanguage))
                snapshotRow(
                    L.tr("toggle.translate_to_english"),
                    snapshot.translatesToEnglish ? L.tr("common.on") : L.tr("common.off")
                )
                snapshotRow(
                    L.tr("label.acceleration_mode"),
                    effectiveAccelerationText(snapshot)
                )
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text(summaryLine(snapshot))
                    .font(.system(size: UITypographyScale.scaled(13), weight: .medium))
                Spacer()
                Text(L.tr("run.summary.toggle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
        .accessibilityElement(children: .combine)
    }

    private func effectiveAccelerationText(_ snapshot: AppConfigurationSnapshot) -> String {
        let effectiveTitle = model.runEffectiveMode?.title ?? snapshot.accelerationMode.title
        return L.tr("options.acceleration.effective", effectiveTitle)
    }

    private func summaryLine(_ snapshot: AppConfigurationSnapshot) -> String {
        "\(L.tr("label.file_count", snapshot.inputFiles.count)) · \(formatsSummaryText(snapshot.outputFormats))"
    }

    private func snapshotRow(_ label: String, _ value: String) -> some View {
        LabeledRow(title: label, secondaryTitle: true) {
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.system(size: UITypographyScale.scaled(13)))
    }

    private var liveTranscriptSection: some View {
        VStack(alignment: .leading, spacing: liveSectionSpacing) {
            HStack {
                SectionHeader(title: L.tr("section.live_transcript"))
                Spacer()
                Text(L.tr("live.segment_count", model.liveSegments.count))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { sectionHeaderHeight = $0 }

            Divider()

            if model.liveSegments.isEmpty {
                Text(L.tr("live.waiting"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: viewportHeight, alignment: .center)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.liveSegments) { segment in
                                TranscriptRow(segment: segment)
                                    .id(segment.id)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: viewportHeight)
                    .onChange(of: model.liveSegments.last?.id) { _, latestID in
                        guard followsLatest, let latestID else { return }
                        if reduceMotion {
                            proxy.scrollTo(latestID, anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(latestID, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            HStack {
                Text(L.tr("live.draft_note"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(L.tr("live.follow_latest"), isOn: $followsLatest)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { followRowHeight = $0 }
        }
    }
}

// MARK: - Result workspace (success / failure / cancelled)

struct RunResultView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.windowSizeMode) private var windowSizeMode
    let outcome: TaskOutcome
    let openLogs: () -> Void
    let openAllOutputs: () -> Void

    private var hasSRT: Bool { !model.previewFiles.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TaskWorkspaceMetrics.sectionSpacing) {
                switch outcome {
                case let .succeeded(inputFileCount, outputFiles):
                    successBody(inputFileCount: inputFileCount, outputFiles: outputFiles)
                case let .failed(summary):
                    failedBody(summary: summary)
                case .cancelled:
                    cancelledBody()
                }
            }
            .padding(.top, TaskWorkspaceMetrics.contentTopPadding)
            .padding(.horizontal, TaskWorkspaceMetrics.contentHorizontalPadding)
            .padding(.bottom, 24)
            .readingColumn(windowSizeMode)
        }
    }

    // MARK: success

    private func successBody(inputFileCount: Int, outputFiles: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(semanticSuccessColor)
                Text(L.tr("result.success_badge"))
                    .fontWeight(.medium)
                    .foregroundStyle(semanticSuccessColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L.tr("result.success.title"))
                    .font(.system(size: UITypographyScale.scaled(22), weight: .semibold))
                Text(L.tr("result.success.detail", inputFileCount, outputFiles.count))
                    .foregroundStyle(.secondary)
            }

            if hasSRT {
                subtitlePicker
                previewSection
            } else if !outputFiles.isEmpty {
                outputPicker(outputFiles)
                Text(L.tr("result.preview_none"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitlePicker: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.tr("result.selected_subtitles"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(L.tr("result.selected_subtitles"), selection: previewSelection) {
                    ForEach(model.previewFiles) { file in
                        Text(pickerTitle(for: file.url, displayName: file.displayName))
                            .tag(Optional(file.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 460, alignment: .leading)
            }
            Spacer()
            Button(L.tr("result.all_outputs")) {
                openAllOutputs()
            }
            .buttonStyle(.bordered)
            .disabled(model.lastRunOutputFiles.isEmpty)
        }
    }

    private func outputPicker(_ outputFiles: [URL]) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.tr("result.selected_outputs"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(L.tr("result.selected_outputs"), selection: resultSelection) {
                    ForEach(outputFiles, id: \.self) { url in
                        Text(pickerTitle(for: url, displayName: url.lastPathComponent))
                            .tag(Optional(url))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 460, alignment: .leading)
            }
            Spacer()
            Button(L.tr("result.all_outputs")) {
                openAllOutputs()
            }
            .buttonStyle(.bordered)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: L.tr("result.preview_caption"))
                Spacer()
                Text("SRT")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider()

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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.previewSegments) { segment in
                        TranscriptRow(segment: segment)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var previewSelection: Binding<URL?> {
        Binding(
            get: { model.selectedPreviewFileID },
            set: { model.selectPreviewFile(id: $0) }
        )
    }

    private var resultSelection: Binding<URL?> {
        Binding(
            get: { model.selectedResultFileID },
            set: { model.selectResultFile(id: $0) }
        )
    }

    private func pickerTitle(for url: URL, displayName: String) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? displayName : "\(displayName) · \(parent)"
    }

    // MARK: failure

    private func failedBody(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(semanticErrorColor)
                Text(L.tr("result.failure.title"))
                    .fontWeight(.medium)
                    .foregroundStyle(semanticErrorColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L.tr("result.failure.title"))
                    .font(.system(size: UITypographyScale.scaled(22), weight: .semibold))
                Text(summary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button(L.tr("bar.view_logs")) {
                    openLogs()
                }
                .buttonStyle(.bordered)
                Button(L.tr("result.retry")) {
                    model.startTranscription()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)
            }
        }
    }

    // MARK: cancelled

    private func cancelledBody() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
                Text(L.tr("result.cancelled.title"))
                    .fontWeight(.medium)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L.tr("result.cancelled.title"))
                    .font(.system(size: UITypographyScale.scaled(22), weight: .semibold))
                Text(L.tr("result.cancelled.detail"))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
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
        }
    }
}
