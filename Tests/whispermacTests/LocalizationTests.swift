import Foundation
import Testing
@testable import whispermac

@Suite(.serialized)
struct LocalizationTests {

    @Test
    func localizedStringResolvesInDefaultLanguage() {
        let result = L.tr("button.start_transcription")
        #expect(!result.isEmpty)
        #expect(result != "button.start_transcription" || result == "Start Transcription")
    }

    @Test
    func localizedStringResolvesForKnownEnglishKey() {
        withLanguage(.english) {
            #expect(L.currentAppLanguage() == .english)
            #expect(L.tr("button.start_transcription") == "Start Transcription")
        }
    }

    @Test
    func localizedStringResolvesForSimplifiedChineseKey() {
        withLanguage(.simplifiedChinese) {
            #expect(L.currentAppLanguage() == .simplifiedChinese)
            #expect(L.tr("button.start_transcription") == "开始转写")
        }
    }

    @Test
    func localizedStringResolvesForJapaneseKey() {
        withLanguage(.japanese) {
            #expect(L.currentAppLanguage() == .japanese)
            let result = L.tr("button.start_transcription")
            #expect(!result.isEmpty)
            #expect(result != "button.start_transcription")
        }
    }

    @Test
    func unknownKeyReturnsKeyAsFallback() {
        let unknownKey = "nonexistent.key.that.does.not.exist"
        let result = L.tr(unknownKey)
        #expect(result == unknownKey)
    }

    @Test
    func localizedStringWithFormatArguments() {
        withLanguage(.english) {
            let result = L.tr("label.file_count", 5)
            #expect(result.contains("5"))
        }
    }

    private func withLanguage(_ language: AppLanguage, block: () -> Void) {
        let defaults = UserDefaults.standard
        let previousValue = defaults.string(forKey: L.appLanguageDefaultsKey)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: L.appLanguageDefaultsKey)
            } else {
                defaults.removeObject(forKey: L.appLanguageDefaultsKey)
            }
        }
        defaults.set(language.rawValue, forKey: L.appLanguageDefaultsKey)
        block()
    }
}
