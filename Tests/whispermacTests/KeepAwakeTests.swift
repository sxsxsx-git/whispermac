import Foundation
import IOKit.pwr_mgt
import Testing
@testable import whispermac

// The IOKit roundtrips here are real: IOPMAssertionCreateWithName works in any
// process, and IOPMCopyAssertionsByProcess exposes the assertion IDs currently
// held by this process, so acquisition and release are observed against the
// system's live power-assertion table rather than a stub.

@Test
func keepAwakePreventsIdleSleepButNotLidClose() {
    // Deliberate choice: only idle sleep is prevented. Closing the lid during a
    // batch is an explicit user decision and must still put the Mac to sleep.
    #expect(KeepAwakeController.assertionType == kIOPMAssertionTypePreventUserIdleSystemSleep)
    #expect(KeepAwakeController.assertionType != kIOPMAssertionTypePreventSystemSleep)
}

@Test
func batchReasonNamesTheApp() {
    #expect(KeepAwakeController.batchReason.contains("WhisperMac"))
}

@Test
func acquireCreatesAssertionHeldByThisProcess() throws {
    let token = try #require(KeepAwakeController.acquire(reason: KeepAwakeController.batchReason))

    #expect(!token.isReleased)
    #expect(processAssertionIDs().contains(token.assertionID))
}

@Test
func explicitReleaseRemovesAssertionAndIsIdempotent() throws {
    let token = try #require(KeepAwakeController.acquire(reason: KeepAwakeController.batchReason))
    let assertionID = token.assertionID

    token.release()

    #expect(token.isReleased)
    #expect(!processAssertionIDs().contains(assertionID))

    // A second release (including the one in deinit) must not double-release.
    token.release()
}

@Test
func nilOutReleasesAssertionViaDeinit() throws {
    var token: KeepAwakeToken? = try #require(KeepAwakeController.acquire(reason: KeepAwakeController.batchReason))
    let assertionID = token?.assertionID ?? 0
    weak var weakToken = token
    #expect(processAssertionIDs().contains(assertionID))

    token = nil

    // The weak reference clearing proves deinit ran; the assertion disappearing
    // from the process's live assertion table proves the real IOPMAssertionRelease.
    #expect(weakToken == nil)
    #expect(!processAssertionIDs().contains(assertionID))
}

/// The assertion IDs this process currently holds, per IOPMCopyAssertionsByProcess
/// (whose per-pid values are arrays of assertion-detail dictionaries).
private func processAssertionIDs() -> Set<IOPMAssertionID> {
    var assertionsByProcess: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&assertionsByProcess) == kIOReturnSuccess,
        let entries = assertionsByProcess?.takeRetainedValue() as? [AnyHashable: Any]
    else { return [] }
    let pid = NSNumber(value: ProcessInfo.processInfo.processIdentifier)
    let assertions = (entries[pid] as? [[String: Any]]) ?? []
    return Set(assertions.compactMap { assertion in
        (assertion["AssertionId"] as? NSNumber).map { IOPMAssertionID(truncatingIfNeeded: $0.intValue) }
    })
}
