import Foundation

struct VADSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var modelPath: String
    var threshold: Double
    var minSpeechDurationMs: Int
    var minSilenceDurationMs: Int
    var speechPadMs: Int

    static let `default` = VADSettings()

    init(
        isEnabled: Bool = false,
        modelPath: String = "",
        threshold: Double = 0.5,
        minSpeechDurationMs: Int = 250,
        minSilenceDurationMs: Int = 500,
        speechPadMs: Int = 200
    ) {
        self.isEnabled = isEnabled
        self.modelPath = modelPath
        self.threshold = Self.validatedThreshold(threshold)
        self.minSpeechDurationMs = min(max(minSpeechDurationMs, 0), 10_000)
        self.minSilenceDurationMs = min(max(minSilenceDurationMs, 0), 10_000)
        self.speechPadMs = min(max(speechPadMs, 0), 5_000)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, modelPath, threshold, minSpeechDurationMs, minSilenceDurationMs, speechPadMs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled,
            modelPath: try values.decodeIfPresent(String.self, forKey: .modelPath) ?? Self.default.modelPath,
            threshold: try values.decodeIfPresent(Double.self, forKey: .threshold) ?? Self.default.threshold,
            minSpeechDurationMs: try values.decodeIfPresent(Int.self, forKey: .minSpeechDurationMs) ?? Self.default.minSpeechDurationMs,
            minSilenceDurationMs: try values.decodeIfPresent(Int.self, forKey: .minSilenceDurationMs) ?? Self.default.minSilenceDurationMs,
            speechPadMs: try values.decodeIfPresent(Int.self, forKey: .speechPadMs) ?? Self.default.speechPadMs
        )
    }

    private static func validatedThreshold(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0.5
    }
}

enum HuggingFaceDownloadSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case official
    case hfMirror
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .official: L.tr("hf.source.official")
        case .hfMirror: L.tr("hf.source.mirror")
        case .custom: L.tr("hf.source.custom")
        }
    }
}

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

    var containsTranscriptContent: Bool {
        TranscriptContentDetector.containsContent(in: outputFiles)
    }
}

enum TranscriptContentDetector {
    static func containsContent(in files: [URL]) -> Bool {
        for file in files {
            guard let data = try? Data(contentsOf: file), !data.isEmpty else { continue }
            switch file.pathExtension.lowercased() {
            case "txt", "srt", "vtt":
                if let text = String(data: data, encoding: .utf8),
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            case "json":
                if jsonContainsTranscriptText(data) { return true }
            default:
                continue
            }
        }
        return false
    }

    private static func jsonContainsTranscriptText(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let dictionary = root as? [String: Any],
              let transcription = dictionary["transcription"] as? [[String: Any]]
        else { return false }
        return transcription.contains { entry in
            guard let text = entry["text"] as? String else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
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
