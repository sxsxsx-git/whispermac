import Foundation

// MARK: - P0.1 presentation-layer state contract
//
// These types describe what the UI may show. They are derived from AppModel's
// published fields and are assigned only in the real start/finish/catch paths —
// the UI must never reconstruct them by parsing localized `statusText`.

/// Stage of an in-flight transcription batch. The service preprocesses every
/// input first and then transcribes the whole batch with a single whisper-cli
/// call, so there is deliberately no per-file transcription phase here.
enum ActiveRunPhase: Equatable {
    /// `currentIndex` is the 0-based index reported by `onInputStageChange`.
    case preparingInputs(currentIndex: Int, total: Int)
    case transcribingBatch(totalFiles: Int)
    /// User requested cancellation; stays until the task actually ends.
    case stopping
}

/// Terminal outcome of the most recent batch. Assigned only when the batch
/// really ended (normal return, thrown error, or cancellation) so the result
/// context survives `isRunning` flipping back to false. 100% progress never
/// implies `.succeeded`.
enum TaskOutcome: Equatable {
    case succeeded(inputFileCount: Int, outputFiles: [URL])
    case failed(summary: String)
    case cancelled
}

/// Readiness of the transcription environment (CLI and model are blockers;
/// a missing Core ML encoder is only a GPU-fallback hint, not a blocker).
enum SetupReadiness: Equatable {
    case emptyQueue
    case missingRuntime(blockers: Set<RuntimeComponent>)
    case ready
}

/// Which main-workspace contents to show. Priority: running > downloading >
/// last terminal outcome > setup.
enum MainContentState: Equatable {
    case running(ActiveRunPhase)
    case downloadingRuntime
    case finished(TaskOutcome)
    case setup(SetupReadiness)
}

/// Why "Start Transcription" cannot run right now; `nil` means enabled.
/// Ordering mirrors the historical `canStart` checks.
enum StartDisabledReason: Equatable {
    case running
    case downloadingRuntime
    case noInputFiles
    case missingWhisperCLI
    case missingModel
    case noOutputFormats
}

enum TaskPresentation {
    /// Pure mapping from model facts to the main workspace state.
    static func mainContent(
        isRunning: Bool,
        isCancelling: Bool,
        isDownloadingRuntime: Bool,
        activePhase: ActiveRunPhase?,
        lastOutcome: TaskOutcome?,
        inputCount: Int,
        blockingRuntimeComponents: Set<RuntimeComponent>
    ) -> MainContentState {
        if isRunning {
            if isCancelling {
                return .running(.stopping)
            }
            switch activePhase {
            case let .preparingInputs(currentIndex, total):
                return .running(.preparingInputs(currentIndex: currentIndex, total: total))
            case let .transcribingBatch(totalFiles):
                return .running(.transcribingBatch(totalFiles: totalFiles))
            case .stopping:
                return .running(.stopping)
            case nil:
                // The batch started but no stage callback arrived yet; the
                // service always preprocesses inputs first.
                return .running(.preparingInputs(currentIndex: 0, total: max(inputCount, 1)))
            }
        }
        if isDownloadingRuntime {
            return .downloadingRuntime
        }
        if let lastOutcome {
            return .finished(lastOutcome)
        }
        // Blocking runtime components outrank the empty-queue hint: a first
        // launch without a model must lead with the fix, not the invitation.
        if blockingRuntimeComponents.isEmpty {
            return inputCount == 0 ? .setup(.emptyQueue) : .setup(.ready)
        }
        return .setup(.missingRuntime(blockers: blockingRuntimeComponents))
    }

    /// Pure mapping for the primary action's availability and disable cause.
    static func startDisabledReason(
        isRunning: Bool,
        isDownloadingRuntime: Bool,
        inputCount: Int,
        hasWhisperCLI: Bool,
        hasModel: Bool,
        outputFormatCount: Int
    ) -> StartDisabledReason? {
        if isRunning {
            return .running
        }
        if isDownloadingRuntime {
            return .downloadingRuntime
        }
        if inputCount == 0 {
            return .noInputFiles
        }
        if !hasWhisperCLI {
            return .missingWhisperCLI
        }
        if !hasModel {
            return .missingModel
        }
        if outputFormatCount == 0 {
            return .noOutputFormats
        }
        return nil
    }
}

/// The frozen configuration a running batch executes with. Views read it for
/// the run summary; it must never be mutated while the batch is in flight.
struct AppConfigurationSnapshot: Equatable {
    let inputFiles: [URL]
    let outputDirectoryPath: String
    let whisperCLIPath: String
    let modelPath: String
    let accelerationMode: AccelerationMode
    let outputFormats: Set<OutputFormat>
    let sourceLanguage: String
    let translatesToEnglish: Bool
}
