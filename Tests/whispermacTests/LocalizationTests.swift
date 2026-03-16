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
