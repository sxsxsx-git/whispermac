import Foundation
import Testing
@testable import whispermac

@Test
func outputPrefixUsesInputDirectoryWhenRequested() {
    let inputURL = URL(fileURLWithPath: "/tmp/media/demo.mp4")
    let outputURL = OutputPaths.outputPrefixURL(for: inputURL, outputDirectory: inputURL.deletingLastPathComponent())
    #expect(outputURL.path == "/tmp/media/demo")
}
