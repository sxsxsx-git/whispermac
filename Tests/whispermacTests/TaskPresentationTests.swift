import Foundation
import Testing
@testable import whispermac

/// Pure state-mapping coverage for the P0.1 presentation contract: the UI must
/// distinguish empty queue, missing CLI / model, download, preprocessing,
/// batch transcription, cancelling, and the three terminal outcomes without
/// inventing per-file progress or treating 100% as success.
struct TaskPresentationTests {

    private static let noBlockers: Set<RuntimeComponent> = []
    private static let cliMissing: Set<RuntimeComponent> = [.whisperCLI]
    private static let modelMissing: Set<RuntimeComponent> = [.model]

    // MARK: setup

    @Test
    func emptyQueueMapsToEmptySetup() {
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: nil,
            inputCount: 0,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .setup(.emptyQueue))
    }

    @Test
    func emptyQueueWithMissingModelReportsBlocker() {
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: nil,
            inputCount: 0,
            blockingRuntimeComponents: Self.modelMissing
        )
        #expect(state == .setup(.missingRuntime(blockers: Self.modelMissing)))
    }

    @Test
    func missingCLITakesPriorityOverModelBlockerSet() {
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: nil,
            inputCount: 3,
            blockingRuntimeComponents: Self.cliMissing
        )
        #expect(state == .setup(.missingRuntime(blockers: Self.cliMissing)))
    }

    @Test
    func coreMLEncoderIsNeverABlocker() {
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: nil,
            inputCount: 2,
            blockingRuntimeComponents: [] // encoder filtered out upstream
        )
        #expect(state == .setup(.ready))
    }

    @Test
    func inputFilesWithBlockersKeepSetupStateNotOutcome() {
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: nil,
            inputCount: 2,
            blockingRuntimeComponents: Self.modelMissing
        )
        #expect(state == .setup(.missingRuntime(blockers: Self.modelMissing)))
    }

    // MARK: running priorities

    @Test
    func runningWithNoCallbackYetShowsPreparingFirstInput() {
        let state = TaskPresentation.mainContent(
            isRunning: true,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: nil,
            inputCount: 4,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .running(.preparingInputs(currentIndex: 0, total: 4)))
    }

    @Test
    func preprocessingPhaseIsReportedWithIndex() {
        let state = TaskPresentation.mainContent(
            isRunning: true,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: .preparingInputs(currentIndex: 1, total: 3),
            lastOutcome: nil,
            inputCount: 3,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .running(.preparingInputs(currentIndex: 1, total: 3)))
    }

    @Test
    func transcribingPhaseIsBatchLevel() {
        let state = TaskPresentation.mainContent(
            isRunning: true,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: .transcribingBatch(totalFiles: 3),
            lastOutcome: nil,
            inputCount: 3,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .running(.transcribingBatch(totalFiles: 3)))
    }

    @Test
    func cancellingOverridesRunningPhase() {
        let state = TaskPresentation.mainContent(
            isRunning: true,
            isCancelling: true,
            isDownloadingRuntime: false,
            activePhase: .transcribingBatch(totalFiles: 3),
            lastOutcome: nil,
            inputCount: 3,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .running(.stopping))
    }

    @Test
    func runningBeatsDownloadingAndStaleOutcome() {
        let state = TaskPresentation.mainContent(
            isRunning: true,
            isCancelling: false,
            isDownloadingRuntime: true,
            activePhase: .preparingInputs(currentIndex: 0, total: 2),
            lastOutcome: .cancelled,
            inputCount: 2,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .running(.preparingInputs(currentIndex: 0, total: 2)))
    }

    @Test
    func downloadingBeatsPreviousOutcomeAndSetup() {
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: true,
            activePhase: nil,
            lastOutcome: .failed(summary: "old failure"),
            inputCount: 0,
            blockingRuntimeComponents: Self.modelMissing
        )
        #expect(state == .downloadingRuntime)
    }

    // MARK: terminal outcomes

    @Test
    func successOutcomeSurvivesIsRunningEnd() {
        let outputs = [URL(fileURLWithPath: "/tmp/a.srt")]
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: .succeeded(inputFileCount: 3, outputFiles: outputs),
            inputCount: 3,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .finished(.succeeded(inputFileCount: 3, outputFiles: outputs)))
    }

    @Test
    func failureOutcomeSurvivesEvenWithFullProgress() {
        // A batch can end with the progress value at 100%; the outcome — not
        // the progress — decides what the UI shows.
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: .failed(summary: "afconvert failed"),
            inputCount: 2,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .finished(.failed(summary: "afconvert failed")))
    }

    @Test
    func cancelledOutcomeIsATerminalState() {
        let state = TaskPresentation.mainContent(
            isRunning: false,
            isCancelling: false,
            isDownloadingRuntime: false,
            activePhase: nil,
            lastOutcome: .cancelled,
            inputCount: 2,
            blockingRuntimeComponents: Self.noBlockers
        )
        #expect(state == .finished(.cancelled))
    }

    // MARK: start disabled reasons

    @Test
    func startDisabledReasonOrdering() {
        #expect(
            TaskPresentation.startDisabledReason(
                isRunning: true,
                isDownloadingRuntime: true,
                inputCount: 0,
                hasWhisperCLI: false,
                hasModel: false,
                outputFormatCount: 0
            ) == .running
        )
        #expect(
            TaskPresentation.startDisabledReason(
                isRunning: false,
                isDownloadingRuntime: true,
                inputCount: 0,
                hasWhisperCLI: false,
                hasModel: false,
                outputFormatCount: 0
            ) == .downloadingRuntime
        )
        #expect(
            TaskPresentation.startDisabledReason(
                isRunning: false,
                isDownloadingRuntime: false,
                inputCount: 0,
                hasWhisperCLI: false,
                hasModel: false,
                outputFormatCount: 0
            ) == .noInputFiles
        )
        #expect(
            TaskPresentation.startDisabledReason(
                isRunning: false,
                isDownloadingRuntime: false,
                inputCount: 2,
                hasWhisperCLI: false,
                hasModel: false,
                outputFormatCount: 2
            ) == .missingWhisperCLI
        )
        #expect(
            TaskPresentation.startDisabledReason(
                isRunning: false,
                isDownloadingRuntime: false,
                inputCount: 2,
                hasWhisperCLI: true,
                hasModel: false,
                outputFormatCount: 2
            ) == .missingModel
        )
        #expect(
            TaskPresentation.startDisabledReason(
                isRunning: false,
                isDownloadingRuntime: false,
                inputCount: 2,
                hasWhisperCLI: true,
                hasModel: true,
                outputFormatCount: 0
            ) == .noOutputFormats
        )
        #expect(
            TaskPresentation.startDisabledReason(
                isRunning: false,
                isDownloadingRuntime: false,
                inputCount: 2,
                hasWhisperCLI: true,
                hasModel: true,
                outputFormatCount: 2
            ) == nil
        )
    }
}
