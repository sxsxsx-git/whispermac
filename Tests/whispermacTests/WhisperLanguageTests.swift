import Foundation
import Testing
@testable import whispermac

@Test
func curatedLanguageListContainsExactlyTheDocumentedCodesInStableOrder() {
    let codes = WhisperLanguage.common.map(\.code)

    #expect(codes == ["en", "zh", "ja", "ko", "de", "fr", "es", "ru", "pt", "it", "ar", "hi"])
}

@Test
func curatedLanguageDisplayNamesAreNonEmpty() {
    for language in WhisperLanguage.common {
        #expect(!language.displayName.isEmpty)
        #expect(language.displayName == language.nativeName)
    }
}

@Test
func autoIsSpecialCased() {
    #expect(WhisperLanguage.auto.code == "auto")
    #expect(WhisperLanguage.auto.nativeName == nil)
    #expect(!WhisperLanguage.auto.displayName.isEmpty)
    #expect(WhisperLanguage.auto.displayName != "auto")
    #expect(!WhisperLanguage.common.contains { $0.code == WhisperLanguage.autoCode })
}

@Test
func supportedCodesAreAutoPlusCuratedList() {
    #expect(WhisperLanguage.isSupported("auto"))
    #expect(WhisperLanguage.isSupported("ja"))
    #expect(!WhisperLanguage.isSupported("xx"))
    #expect(!WhisperLanguage.isSupported(""))
}
