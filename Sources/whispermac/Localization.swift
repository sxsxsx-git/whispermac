import Foundation

/// Private class used to locate the module's resource bundle via `Bundle(for:)`.
private final class _BundleLocator {}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese
    case japanese

    var id: String { rawValue }

    var localizationIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .japanese:
            return "ja"
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return L.tr("language.system")
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .japanese:
            return "日本語"
        }
    }

    init(storedValue: String?) {
        self = AppLanguage(rawValue: storedValue ?? "") ?? .system
    }

    init(identifier: String) {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        switch normalized {
        case "en", "en-us", "en-gb":
            self = .english
        case "zh", "zh-cn", "zh-hans", "zh-sg":
            self = .simplifiedChinese
        case "ja", "ja-jp":
            self = .japanese
        default:
            self = .system
        }
    }
}

enum L {
    static let appLanguageDefaultsKey = "appLanguage"

    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedString(key)
        guard !arguments.isEmpty else {
            return format
        }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static func localizedString(_ key: String) -> String {
        let appLanguage = currentAppLanguage()
        if let languageOverride = appLanguage.localizationIdentifier,
           let path = resourceBundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: languageOverride),
           let dict = NSDictionary(contentsOfFile: path) as? [String: String],
           let value = dict[key] {
            return value
        }
        return resourceBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    private static let resourceBundle: Bundle = {
        let spmBundleName = "whispermac_whispermac"

        // 1. Try Bundle.main — works for distributed .app bundles where
        //    .lproj directories are placed directly inside Contents/Resources/.
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return Bundle.main
        }

        // 2. Try SPM resource bundle embedded inside the app bundle.
        if let url = Bundle.main.url(forResource: spmBundleName, withExtension: "bundle"),
           let bundle = Bundle(url: url)
        {
            return bundle
        }

        // 3. Search candidate directories for the SPM resource bundle.
        //    Includes the module's own resource URL and its parent (for xctest).
        let moduleBundle = Bundle(for: _BundleLocator.self)
        let candidates: [URL?] = [
            moduleBundle.resourceURL,
            moduleBundle.bundleURL.deletingLastPathComponent(),
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ]
        for candidate in candidates {
            if let candidate {
                let bundlePath = candidate.appendingPathComponent(spmBundleName + ".bundle")
                if let bundle = Bundle(url: bundlePath) {
                    return bundle
                }
            }
        }

        // 4. Last resort: return Bundle.main and let localizedString fall back
        //    to returning the key as-is when the table is not found.
        return Bundle.main
    }()

    static func currentAppLanguage() -> AppLanguage {
        let environment = ProcessInfo.processInfo.environment
        if let rawValue = environment["WHISPERMAC_LANGUAGE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawValue.isEmpty {
            return AppLanguage(identifier: rawValue)
        }

        let storedValue = UserDefaults.standard.string(forKey: appLanguageDefaultsKey)
        return AppLanguage(storedValue: storedValue)
    }

    static func setAppLanguage(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: appLanguageDefaultsKey)
        } else {
            UserDefaults.standard.set(language.rawValue, forKey: appLanguageDefaultsKey)
        }
    }
}
