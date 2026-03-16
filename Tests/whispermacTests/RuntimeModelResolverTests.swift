import Foundation
import Testing
@testable import whispermac

@Test
func gpuAndANEFallsBackWhenCoreMLIsMissing() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let modelURL = root.appending(path: "ggml-large-v3-turbo.bin")
    FileManager.default.createFile(atPath: modelURL.path, contents: Data())

    let plan = try RuntimeModelResolver.prepare(modelPath: modelURL.path, requestedMode: .gpuAndANE)

    #expect(plan.effectiveMode == .pureGPU)
    #expect(plan.executionModelPath == modelURL.path)
    #expect(plan.coreMLAvailable == false)
}

@Test
func pureGPUUsesAlternateRuntimePathWhenCoreMLExists() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let modelURL = root.appending(path: "ggml-large-v3-turbo.bin")
    let coreMLURL = OutputPaths.coreMLModelURL(for: modelURL)
    FileManager.default.createFile(atPath: modelURL.path, contents: Data())
    try FileManager.default.createDirectory(at: coreMLURL, withIntermediateDirectories: true)

    let plan = try RuntimeModelResolver.prepare(modelPath: modelURL.path, requestedMode: .pureGPU)

    #expect(plan.effectiveMode == .pureGPU)
    #expect(plan.executionModelPath != modelURL.path)
    #expect(FileManager.default.fileExists(atPath: plan.executionModelPath))
}
