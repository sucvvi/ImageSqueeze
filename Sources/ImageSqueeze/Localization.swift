import Foundation

/// Interface language. Stored separately from `Settings` so "恢复默认 / Reset" doesn't change it.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("跟随系统", "System")
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }

    var isChinese: Bool {
        switch self {
        case .zh: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    private static let key = "ImageSqueeze.language"

    static func load() -> AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}

enum L10n {
    /// Read from engine threads too; only written on the main thread when the user switches language.
    nonisolated(unsafe) static var isChinese = AppLanguage.load().isChinese
}

/// Picks the Chinese or English text for the current interface language.
func L(_ zh: String, _ en: String) -> String {
    L10n.isChinese ? zh : en
}
