import UIKit

/// Общая реакция на тап по кнопке установки: проверки до старта, отмена, повтор после ошибки.
@MainActor
enum InstallPrompter {
    static func handleTap(app: AppSummary, service: InstallService, from controller: UIViewController) {
        let state = service.state(for: app.id)
        switch state {
        case .failed(let code):
            let alert = UIAlertController(
                title: InstallErrorText.title(for: code),
                message: InstallErrorText.message(for: code),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.tr("common.close"), style: .cancel) { _ in
                service.dismiss(appId: app.id)
            })
            alert.addAction(UIAlertAction(title: L10n.tr("common.retry"), style: .default) { _ in
                service.dismiss(appId: app.id)
                start(app: app, service: service, from: controller)
            })
            controller.present(alert, animated: true)
        case .preparing, .ready, .handingOff, .installing:
            let alert = UIAlertController(
                title: L10n.tr("install.cancel.title", app.name),
                message: L10n.tr("install.cancel.message"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.tr("install.cancel.keep"), style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.tr("install.cancel.confirm"), style: .destructive) { _ in
                service.cancel(appId: app.id)
            })
            controller.present(alert, animated: true)
        case .idle:
            start(app: app, service: service, from: controller)
        }
    }

    static func start(app: AppSummary, service: InstallService, from controller: UIViewController) {
        let result = service.start(app)
        guard case .blocked(let reason) = result else { return }
        switch reason {
        case .ok:
            break
        case .incompatible(let requiredOS):
            controller.presentErrorAlert(
                title: L10n.tr("install.error.incompatible.title"),
                message: L10n.tr("install.incompatible.message_format", requiredOS)
            )
        case .unavailable:
            controller.presentErrorAlert(
                title: L10n.tr("install.error.unavailable.title"),
                message: L10n.tr("install.error.unavailable.message")
            )
        case .lowSpace(let requiredBytes, let freeBytes):
            let alert = UIAlertController(
                title: L10n.tr("install.error.space.title"),
                message: L10n.tr(
                    "install.space.message_format",
                    Formatters.bytes(max(0, requiredBytes - freeBytes))
                ),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.tr("common.cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.tr("install.space.install_anyway"), style: .default) { _ in
                service.start(app, allowLowSpace: true)
            })
            controller.present(alert, animated: true)
        }
    }
}
