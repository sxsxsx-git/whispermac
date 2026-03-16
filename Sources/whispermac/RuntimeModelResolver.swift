import CryptoKit
import Foundation

enum RuntimeModelResolverError: LocalizedError {
    case missingModel(String)
    case failedToCreateGPUOnlyLink(String)

    var errorDescription: String? {
        switch self {
        case .missingModel(let path):
            return "模型文件不存在: \(path)"
        case .failedToCreateGPUOnlyLink(let path):
            return "创建纯 GPU 运行模型失败: \(path)"
        }
    }
}

struct RuntimeModelPlan: Sendable {
    let requestedMode: AccelerationMode
    let effectiveMode: AccelerationMode
    let originalModelPath: String
    let executionModelPath: String
    let coreMLModelPath: String
    let coreMLAvailable: Bool
    let notes: [String]
}

enum RuntimeModelResolver {
    static func prepare(modelPath: String, requestedMode: AccelerationMode) throws -> RuntimeModelPlan {
        let originalPath = PathResolver.expandingTilde(modelPath)
        guard FileManager.default.fileExists(atPath: originalPath) else {
            throw RuntimeModelResolverError.missingModel(originalPath)
        }

        let originalURL = URL(fileURLWithPath: originalPath)
        let coreMLURL = OutputPaths.coreMLModelURL(for: originalURL)
        let hasCoreML = FileManager.default.fileExists(atPath: coreMLURL.path)
        var effectiveMode = requestedMode
        var executionPath = originalPath
        var notes: [String] = []

        switch requestedMode {
        case .gpuAndANE:
            if hasCoreML {
                notes.append("检测到 Core ML encoder，将启用 GPU + ANE 路径。")
            } else {
                effectiveMode = .pureGPU
                notes.append("未找到 Core ML encoder，已回退为纯 GPU 模式。")
            }
        case .pureGPU:
            if hasCoreML {
                executionPath = try prepareGPUOnlyModelLink(for: originalURL)
                notes.append("已为纯 GPU 模式创建无 Core ML companion 的运行时模型路径。")
            } else {
                notes.append("当前模型本身没有 Core ML encoder，将直接按纯 GPU 运行。")
            }
        }

        return RuntimeModelPlan(
            requestedMode: requestedMode,
            effectiveMode: effectiveMode,
            originalModelPath: originalPath,
            executionModelPath: executionPath,
            coreMLModelPath: coreMLURL.path,
            coreMLAvailable: hasCoreML,
            notes: notes
        )
    }

    private static func prepareGPUOnlyModelLink(for originalURL: URL) throws -> String {
        let runtimeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "whispermac-runtime-models", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)

        let stem = originalURL.deletingPathExtension().lastPathComponent
        let hash = shortHash(for: originalURL.path)
        let runtimeURL = runtimeDirectory.appending(path: "\(stem)-gpu-only-\(hash).bin")

        if FileManager.default.fileExists(atPath: runtimeURL.path) {
            let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: runtimeURL.path)
            if destination == originalURL.path {
                return runtimeURL.path
            }
            try? FileManager.default.removeItem(at: runtimeURL)
        }

        do {
            try FileManager.default.createSymbolicLink(at: runtimeURL, withDestinationURL: originalURL)
            return runtimeURL.path
        } catch {
            throw RuntimeModelResolverError.failedToCreateGPUOnlyLink(runtimeURL.path)
        }
    }

    private static func shortHash(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
