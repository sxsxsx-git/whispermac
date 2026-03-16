import Foundation
import Testing
@testable import whispermac

@Test
func coreMLModelPathUsesEncoderSuffix() {
    let modelURL = URL(fileURLWithPath: "/tmp/Models/ggml-large-v3-turbo.bin")
    #expect(OutputPaths.coreMLModelURL(for: modelURL).path == "/tmp/Models/ggml-large-v3-turbo-encoder.mlmodelc")
}

@Test
func outputFilesMatchSelectedFormats() {
    let inputURL = URL(fileURLWithPath: "/tmp/demo.mp4")
    let outputDirectory = URL(fileURLWithPath: "/tmp/out")
    let files = OutputPaths.outputFiles(for: inputURL, outputDirectory: outputDirectory, formats: [.srt, .txt])
    #expect(files.map { $0.lastPathComponent } == ["demo.srt", "demo.txt"])
}
