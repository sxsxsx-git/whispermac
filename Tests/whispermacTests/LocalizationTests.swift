import Foundation
import Testing
@testable import whispermac

@Test
func localizedStringResolvesInDefaultLanguage() {
    let result = L.tr("button.start_transcription")
    #expect(!result.isEmpty)
    #expect(result != "button.start_transcription" || result == "Start Transcription")
}

@Test
func localizedStringResolvesForKnownEnglishKey() {
    // Temporarily set language to English
    let defaults = UserDefaults.standard
    let previousValue = defaults.string(forKey: L.appLanguageDefaultsKey)
    defer {
        if let previousValue {
            defaults.set(previousValue, forKey: L.appLanguageDefaultsKey)
        } else {
            defaults.removeObject(forKey: L.appLanguageDefaultsKey)
        }
    }

    defaults.set(AppLanguage.english.rawValue, forKey: L.appLanguageDefaultsKey)

    #expect(L.currentAppLanguage() == .english)
    #expect(L.tr("button.start_transcription") == "Start Transcription")
}

@Test
func localizedStringResolvesForSimplifiedChineseKey() {
    let defaults = UserDefaults.standard
    let previousValue = defaults.string(forKey: L.appLanguageDefaultsKey)
    defer {
        if let previousValue {
            defaults.set(previousValue, forKey: L.appLanguageDefaultsKey)
        } else {
            defaults.removeObject(forKey: L.appLanguageDefaultsKey)
        }
    }

    defaults.set(AppLanguage.simplifiedChinese.rawValue, forKey: L.appLanguageDefaultsKey)

    #expect(L.currentAppLanguage() == .simplifiedChinese)
    #expect(L.tr("button.start_transcription") == "开始转写")
}

@Test
func localizedStringResolvesForJapaneseKey() {
    let defaults = UserDefaults.standard
    let previousValue = defaults.string(forKey: L.appLanguageDefaultsKey)
    defer {
        if let previousValue {
            defaults.set(previousValue, forKey: L.appLanguageDefaultsKey)
        } else {
            defaults.removeObject(forKey: L.appLanguageDefaultsKey)
        }
    }

    defaults.set(AppLanguage.japanese.rawValue, forKey: L.appLanguageDefaultsKey)

    #expect(L.currentAppLanguage() == .japanese)
    let result = L.tr("button.start_transcription")
    #expect(!result.isEmpty)
    #expect(result != "button.start_transcription")
}

@Test
func unknownKeyReturnsKeyAsFallback() {
    let unknownKey = "nonexistent.key.that.does.not.exist"
    let result = L.tr(unknownKey)
    // localizedString(forKey:value:table:) returns the key when not found
    #expect(result == unknownKey)
}

@Test
func localizedStringWithFormatArguments() {
    let defaults = UserDefaults.standard
    let previousValue = defaults.string(forKey: L.appLanguageDefaultsKey)
    defer {
        if let previousValue {
            defaults.set(previousValue, forKey: L.appLanguageDefaultsKey)
        } else {
            defaults.removeObject(forKey: L.appLanguageDefaultsKey)
        }
    }

    defaults.set(AppLanguage.english.rawValue, forKey: L.appLanguageDefaultsKey)

    let result = L.tr("label.file_count", 5)
    #expect(result.contains("5"))
}
