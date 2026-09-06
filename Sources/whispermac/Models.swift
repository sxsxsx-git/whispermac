import Foundation

enum OutputFormat: String, CaseIterable, Hashable, Sendable {
    case txt
    case srt
    case vtt
    case json

    var whisperArgument: String {
        switch self {
        case .txt:
            return "-otxt"
        case .srt:
            return "-osrt"
        case .vtt:
            return "-ovtt"
        case .json:
            return "-oj"
        }
    }
}

struct WhisperLanguage: Hashable, Sendable, Identifiable {
    let code: String
    let nativeName: String?

    var id: String { code }

    var displayName: String {
        guard let nativeName else {
            return L.tr("language.auto")
        }
        return nativeName
    }

    static let autoCode = "auto"
    static let auto = WhisperLanguage(code: autoCode, nativeName: nil)
    static let common: [WhisperLanguage] = [
        WhisperLanguage(code: "en", nativeName: "English"),
        WhisperLanguage(code: "zh", nativeName: "中文"),
        WhisperLanguage(code: "ja", nativeName: "日本語"),
        WhisperLanguage(code: "ko", nativeName: "한국어"),
        WhisperLanguage(code: "de", nativeName: "Deutsch"),
        WhisperLanguage(code: "fr", nativeName: "Français"),
        WhisperLanguage(code: "es", nativeName: "Español"),
        WhisperLanguage(code: "ru", nativeName: "Русский"),
        WhisperLanguage(code: "pt", nativeName: "Português"),
        WhisperLanguage(code: "it", nativeName: "Italiano"),
        WhisperLanguage(code: "ar", nativeName: "العربية"),
        WhisperLanguage(code: "hi", nativeName: "हिन्दी"),
    ]

    static func isSupported(_ code: String) -> Bool {
        code == autoCode || common.contains { $0.code == code }
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
