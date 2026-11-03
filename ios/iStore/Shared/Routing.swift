import UIKit

/// Переходы между фичами. Реализует `AppFlowController`, фичи друг о друге не знают.
@MainActor
protocol AppRouting: AnyObject {
    func showAppDetail(appId: String, summary: AppSummary?, from source: UIViewController)
    func showRoom(id: String, title: String?, from source: UIViewController)
    func showCategory(id: String, name: String, from source: UIViewController)
    func showAccount(from source: UIViewController)
    func showVersionHistory(appId: String, appName: String, from source: UIViewController)
    func openExternal(_ url: URL, from source: UIViewController)
}

extension UIViewController {
    /// Кнопка аккаунта (аватар) для навбара вкладки.
    func makeAccountBarButton(target: Any?, action: Selector) -> UIBarButtonItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let image = UIImage(systemName: "person.crop.circle.fill", withConfiguration: configuration)
        let item = UIBarButtonItem(image: image, style: .plain, target: target, action: action)
        item.accessibilityLabel = L10n.tr("account.title")
        return item
    }
}
