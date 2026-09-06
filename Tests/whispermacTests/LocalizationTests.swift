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

private let allLocalizationIdentifiers = ["en", "zh-hans", "ja"]

private func localizationKeys(for identifier: String) throws -> Set<String> {
    let path = try #require(
        Bundle.module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: identifier)
    )
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
    let table = try #require(propertyList as? [String: String])
    return Set(table.keys)
}

@Test
func localizationKeysHaveParityAcrossAllBundles() throws {
    var keySets: [String: Set<String>] = [:]
    for identifier in allLocalizationIdentifiers {
        keySets[identifier] = try localizationKeys(for: identifier)
    }

    #expect(keySets["en"] == keySets["zh-hans"])
    #expect(keySets["en"] == keySets["ja"])
}

@Test(arguments: allLocalizationIdentifiers)
func audioLanguageAndTranslateKeysResolveInEveryBundle(identifier: String) throws {
    let path = try #require(Bundle.module.path(forResource: identifier, ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))

    for key in ["language.auto", "label.audio_language", "toggle.translate_to_english", "hint.translate_to_english", "toggle.export_vtt", "toggle.export_json"] {
        let value = bundle.localizedString(forKey: key, value: "", table: "Localizable")
        #expect(!value.isEmpty, "\(key) is empty in \(identifier)")
        #expect(value != key, "\(key) is missing from \(identifier)")
    }
}
