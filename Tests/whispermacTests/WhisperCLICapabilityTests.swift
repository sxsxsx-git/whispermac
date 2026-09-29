import Testing
@testable import whispermac

@Test
func vadCapabilityRequiresBothLongOptionsInHelpOutput() {
    #expect(WhisperCLICapabilityChecker.helpOutputSupportsVAD("--vad Enable VAD\n-vm FNAME, --vad-model FNAME\n"))
    #expect(!WhisperCLICapabilityChecker.helpOutputSupportsVAD("--vad Enable VAD\n-vm FNAME\n"))
    #expect(!WhisperCLICapabilityChecker.helpOutputSupportsVAD("--vad-model FNAME\n"))
}
