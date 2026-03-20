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
