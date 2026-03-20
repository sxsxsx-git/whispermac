import Foundation

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
        let format = localizationBundle.localizedString(forKey: key, value: key, table: "Localizable")
        guard !arguments.isEmpty else {
            return format
        }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static var localizationBundle: Bundle {
        let appLanguage = currentAppLanguage()
        guard let languageOverride = appLanguage.localizationIdentifier else {
            return Bundle.module
        }

        guard
            let path = Bundle.module.path(forResource: languageOverride, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return Bundle.module
        }

        return bundle
    }

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
