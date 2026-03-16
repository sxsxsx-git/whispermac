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
            return L.tr("mode.pure_gpu_title")
        case .gpuAndANE:
            return L.tr("mode.gpu_ane_title")
        }
    }

    var detail: String {
        switch self {
        case .pureGPU:
            return L.tr("mode.pure_gpu_detail")
        case .gpuAndANE:
            return L.tr("mode.gpu_ane_detail")
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
            return L.tr("stage.preparing")
        case .extractingAudio:
            return L.tr("stage.extracting_audio")
        case .transcribing:
            return L.tr("stage.transcribing")
        case .finished:
            return L.tr("stage.finished")
        }
    }
}
