import Foundation

/// Доступ к `Localizable.strings`. Все пользовательские строки берутся отсюда.
enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: Locale.current, arguments: args)
    }

    /// Язык интерфейса для `Accept-Language`: `ru` или `en`.
    static var apiLanguage: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return preferred.hasPrefix("ru") ? "ru" : "en"
    }
}

extension String {
    /// Ключ локализации → строка.
    var localized: String {
        L10n.tr(self)
    }
}
