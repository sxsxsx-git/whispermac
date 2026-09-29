import Testing
@testable import whispermac

@Test
func coreMLRuntimeLogDistinguishesLoadedFromFailedEncoder() {
    #expect(RuntimeAccelerationSignal.parse("whisper_init_state: Core ML model loaded") == .coreMLLoaded)
    #expect(RuntimeAccelerationSignal.parse("whisper_init_state: failed to load Core ML model") == .coreMLFailed)
    #expect(RuntimeAccelerationSignal.parse("whisper_backend_init_gpu: no GPU found") == nil)
}
