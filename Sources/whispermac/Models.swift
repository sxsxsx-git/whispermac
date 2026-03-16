import Foundation

enum OutputFormat: String, CaseIterable, Hashable, Sendable {
    case txt
    case srt

    var whisperArgument: String {
        switch self {
        case .txt:
            return "-otxt"
        case .srt:
            return "-osrt"
        }
    }
}

struct TranscriptionReport: Sendable {
    let audioPreparationCommand: String
    let whisperCommand: String
    let outputFiles: [URL]
}

enum AccelerationMode: String, CaseIterable, Hashable, Sendable {
    case pureGPU
    case gpuAndANE

    var title: String {
        switch self {
        case .pureGPU:
            return "纯 GPU"
        case .gpuAndANE:
            return "GPU + ANE"
        }
    }

    var detail: String {
        switch self {
        case .pureGPU:
            return "禁用 Core ML encoder，Whisper 尽量只走 Metal GPU。"
        case .gpuAndANE:
            return "encoder 走 Core ML / ANE，decoder 继续走 Metal GPU。"
        }
    }
}

enum TranscriptionStage: String, Sendable {
    case preparing
    case extractingAudio
    case transcribing
    case finished

    var progressValue: Double {
        switch self {
        case .preparing:
            return 0.05
        case .extractingAudio:
            return 0.35
        case .transcribing:
            return 0.9
        case .finished:
            return 1.0
        }
    }

    var description: String {
        switch self {
        case .preparing:
            return "准备中"
        case .extractingAudio:
            return "提取音频"
        case .transcribing:
            return "Whisper 转写"
        case .finished:
            return "已完成"
        }
    }
}
