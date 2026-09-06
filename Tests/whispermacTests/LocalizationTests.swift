import Foundation
import Testing
@testable import whispermac

@Test
func localizationBundlesExist() {
    #expect(Bundle.module.localizations.contains("en"))
    #expect(Bundle.module.localizations.contains("zh-hans"))
    #expect(Bundle.module.localizations.contains("ja"))
}

@Test
func localizedModeTitleResolves() {
    #expect(!L.tr("mode.pure_gpu_title").isEmpty)
}

@Test
func englishLocalizationBundleExists() {
    let path = Bundle.module.path(forResource: "en", ofType: "lproj")
    #expect(path != nil)
}

@Test
func storedLanguageOverrideCanSwitchToEnglish() {
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
