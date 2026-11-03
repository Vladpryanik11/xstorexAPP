import UIKit
import UserNotifications

/// Запрос разрешения на уведомления. Экраны зависят от протокола, а не от `PushCoordinator`.
@MainActor
protocol PushPermissionRequesting: AnyObject {
    /// Системный запрос показывается один раз; после «Разрешить» приложение регистрируется в APNs.
    func requestAuthorizationIfNeeded()
}

/// Тело `POST /client/push-token` (API.md).
struct PushTokenBody: Encodable, Sendable, Equatable {
    let apnsToken: String
    let apnsEnv: String
    let locale: String
    let tzOffsetMinutes: Int

    enum CodingKeys: String, CodingKey {
        case apnsToken = "apns_token"
        case apnsEnv = "apns_env"
        case locale
        case tzOffsetMinutes = "tz_offset_minutes"
    }
}

/// Push-уведомления: разрешение, регистрация токена APNs на сервере, нажатие на уведомление.
@MainActor
final class PushCoordinator: NSObject, PushPermissionRequesting {
    /// Открыть карточку приложения. Пока обработчика нет (холодный старт), `app_id` ждёт его.
    var onOpenApp: ((String) -> Void)? {
        didSet { deliverPendingApp() }
    }

    private let api: APIClientProtocol
    private let tokenStore: TokenStoring
    private let environment: String
    private let registerForRemote: @MainActor () -> Void
    private var pendingAppId: String?

    init(
        api: APIClientProtocol,
        tokenStore: TokenStoring,
        environment: String,
        registerForRemote: @escaping @MainActor () -> Void = { UIApplication.shared.registerForRemoteNotifications() }
    ) {
        self.api = api
        self.tokenStore = tokenStore
        self.environment = environment
        self.registerForRemote = registerForRemote
        super.init()
    }

    // MARK: - Разрешение и регистрация

    func requestAuthorizationIfNeeded() {
        Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            switch status {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if granted {
                    self?.registerForRemote()
                }
            case .authorized, .provisional, .ephemeral:
                self?.registerForRemote()
            default:
                break
            }
        }
    }

    /// При запуске и после входа: Apple советует регистрироваться заново, токен APNs может смениться.
    func refreshRegistration() {
        Task { [weak self] in
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .authorized || status == .provisional || status == .ephemeral {
                self?.registerForRemote()
            }
        }
    }

    /// Токен от APNs уходит на сервер. Без входа он не нужен: после входа регистрация повторится.
    func didRegister(deviceToken: Data) async {
        guard await tokenStore.token() != nil else { return }
        let body = PushTokenBody(
            apnsToken: Self.hexString(from: deviceToken),
            apnsEnv: environment,
            locale: L10n.apiLanguage,
            tzOffsetMinutes: TimeZone.current.secondsFromGMT() / 60
        )
        _ = try? await api.send(Endpoint<EmptyResponse>.json(path: "/client/push-token", body: body))
    }

    nonisolated static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Нажатие на уведомление

    /// `app_id` из payload уведомления (API.md, раздел «Push»).
    nonisolated static func appId(from userInfo: [AnyHashable: Any]) -> String? {
        guard let id = userInfo["app_id"] as? String, !id.isEmpty, id.count <= 80 else { return nil }
        return id
    }

    func open(appId: String) {
        if let onOpenApp = onOpenApp {
            onOpenApp(appId)
        } else {
            pendingAppId = appId
        }
    }

    private func deliverPendingApp() {
        guard let appId = pendingAppId, let onOpenApp = onOpenApp else { return }
        pendingAppId = nil
        onOpenApp(appId)
    }
}

extension PushCoordinator: UNUserNotificationCenterDelegate {
    /// В открытом приложении уведомление тоже показывается баннером.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let appId = Self.appId(from: response.notification.request.content.userInfo)
        completionHandler()
        guard let appId = appId else { return }
        Task { @MainActor [weak self] in
            self?.open(appId: appId)
        }
    }
}
