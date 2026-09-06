import Foundation
import IOKit.pwr_mgt
import os

/// Acquires power assertions that keep the Mac awake during transcription batches.
///
/// The assertion type is deliberately `kIOPMAssertionTypePreventUserIdleSystemSleep`:
/// it stops the machine from idle-sleeping while whisper-cli grinds through a long
/// batch, but it does NOT prevent lid-close sleep — closing the lid mid-batch is
/// treated as an explicit user choice. Keep-awake is best-effort: `acquire` returns
/// nil on failure and transcription proceeds without it.
enum KeepAwakeController {
    /// Shown by `pmset -g assertions` while a batch is running.
    static let batchReason = "WhisperMac is transcribing files"

    /// The assertion type requested while a batch runs.
    static let assertionType = kIOPMAssertionTypePreventUserIdleSystemSleep

    static func acquire(reason: String) -> KeepAwakeToken? {
        var assertionID = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        guard status == kIOReturnSuccess else { return nil }
        return KeepAwakeToken(assertionID: assertionID)
    }
}

/// Owns a single IOPMAssertion for its lifetime. Releasing is idempotent and runs
/// automatically on deinit, so the only owner (AppModel) releases by dropping its
/// reference. The C calls are thread-safe and fine to invoke from deinit.
final class KeepAwakeToken: Sendable {
    /// The assertion ID returned by IOPMAssertionCreateWithName.
    let assertionID: IOPMAssertionID

    private let released = OSAllocatedUnfairLock(initialState: false)

    init(assertionID: IOPMAssertionID) {
        self.assertionID = assertionID
    }

    var isReleased: Bool {
        released.withLock { $0 }
    }

    func release() {
        let alreadyReleased = released.withLock { state -> Bool in
            if state { return true }
            state = true
            return false
        }
        guard !alreadyReleased else { return }
        IOPMAssertionRelease(assertionID)
    }

    deinit {
        release()
    }
}
