import UIKit

/// Тексты ошибок API: «что случилось» и «что сделать».
extension APIError {
    var userTitle: String {
        switch self {
        case .offline: return L10n.tr("error.offline.title")
        case .timedOut: return L10n.tr("error.timeout.title")
        case .rateLimited: return L10n.tr("error.rate_limited.title")
        case .accountInactive: return L10n.tr("error.account_inactive.title")
        case .notFound: return L10n.tr("error.not_found.title")
        case .server: return L10n.tr("error.server.title")
        default: return L10n.tr("error.generic.title")
        }
    }

    var userMessage: String {
        switch self {
        case .offline: return L10n.tr("error.offline.message")
        case .timedOut: return L10n.tr("error.timeout.message")
        case .rateLimited: return L10n.tr("error.rate_limited.message")
        case .accountInactive: return L10n.tr("error.account_inactive.message")
        case .notFound: return L10n.tr("error.not_found.message")
        case .server: return L10n.tr("error.server.message")
        default: return L10n.tr("error.generic.message")
        }
    }

    var symbolName: String {
        switch self {
        case .offline, .timedOut, .transport: return "wifi.exclamationmark"
        case .notFound: return "questionmark.app"
        default: return "exclamationmark.triangle"
        }
    }

    static func wrap(_ error: Error) -> APIError {
        APIError.from(transportError: error)
    }
}

extension UIViewController {
    func presentErrorAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.tr("common.ok"), style: .default))
        present(alert, animated: true)
    }

    func presentError(_ error: Error) {
        let apiError = APIError.wrap(error)
        guard apiError != .cancelled else { return }
        presentErrorAlert(title: apiError.userTitle, message: apiError.userMessage)
    }
}
