import SafariServices
import UIKit

/// Роутер приложения. Каталог открывается сразу, а состояние магазина и версия проверяются в фоне.
@MainActor
final class AppFlowController: AppRouting {
    private enum GateLevel {
        static let storeClosed: CGFloat = 30
        static let mandatoryUpdate: CGFloat = 40
    }

    private let container: AppContainer
    private let factory: FeatureFactory
    private weak var windowScene: UIWindowScene?
    let mainWindow: UIWindow

    private var tabBarController: MainTabBarController?
    private var storeClosedWindow: UIWindow?
    private var updateWindow: UIWindow?

    private weak var storeClosedController: StoreClosedViewController?

    private var storePollTask: Task<Void, Never>?
    private var pendingAppId: String?
    private var didCheckClientUpdate = false
    private var isBootstrapped = false

    init(container: AppContainer, windowScene: UIWindowScene) {
        self.container = container
        self.factory = container.featureFactory
        self.windowScene = windowScene
        self.mainWindow = UIWindow(windowScene: windowScene)
        mainWindow.tintColor = Palette.accent
    }

    // MARK: - Запуск

    func start() {
        presentMainInterface()
        mainWindow.makeKeyAndVisible()

        let apiClient = container.apiClient
        let telemetry = container.telemetry
        let errorObserver: APIClient.ErrorObserver = { path, error in
            Task {
                await telemetry.record(kind: "net.error", props: ["path": path, "code": error.code])
            }
        }
        container.push.onOpenApp = { [weak self] appId in
            self?.openApp(id: appId)
        }
        Task { [weak self] in
            await apiClient.setErrorObserver(errorObserver)
            await self?.bootstrap()
        }
    }

    private func bootstrap() async {
        async let storeState: Void = refreshStoreState()
        isBootstrapped = true
        await container.telemetry.record(
            kind: "app.launch",
            props: ["build": container.configuration.build, "version": container.configuration.version]
        )
        await container.telemetry.start()
        await checkClientUpdate()
        await storeState
    }

    // MARK: - Жизненный цикл сцены

    func handleWillEnterForeground() {
        guard isBootstrapped else { return }
        Task { [weak self] in
            guard let self = self else { return }
            await self.container.liveSync.start()
            await self.refreshStoreState()
        }
    }

    func handleDidEnterBackground() {
        let token = BackgroundTaskToken.begin(name: "istore.telemetry.flush")
        let telemetry = container.telemetry
        let liveSync = container.liveSync
        Task {
            await liveSync.stop()
            await telemetry.flush()
            token.end()
        }
    }

    // MARK: - Deeplink `istore://app/<id>`

    func handle(url: URL) {
        guard url.scheme?.lowercased() == "istore" else { return }
        let parts = ([url.host ?? ""] + url.pathComponents).filter { !$0.isEmpty && $0 != "/" }
        guard parts.count >= 2, parts[0] == "app" else { return }
        openApp(id: parts[1])
    }

    /// Карточка приложения из deeplink или push доступна при гостевом запуске.
    func openApp(id appId: String) {
        guard let navigation = currentNavigationController() else {
            pendingAppId = appId
            return
        }
        // Шит аккаунта и другие модальные экраны закрываем, иначе карточка откроется под ними.
        if tabBarController?.presentedViewController != nil {
            tabBarController?.dismiss(animated: false)
        }
        showAppDetail(appId: appId, summary: nil, from: navigation)
    }

    // MARK: - Основной интерфейс

    private func presentMainInterface() {
        if tabBarController == nil {
            let tabs = MainTabBarController(
                factory: factory,
                router: self,
                installService: container.installService
            )
            tabBarController = tabs
            mainWindow.rootViewController = tabs
            UIView.transition(with: mainWindow, duration: 0.3, options: .transitionCrossDissolve, animations: nil)
        }
        let liveSync = container.liveSync
        Task {
            await liveSync.start()
        }
        container.push.refreshRegistration()
        if let appId = pendingAppId, let navigation = currentNavigationController() {
            pendingAppId = nil
            showAppDetail(appId: appId, summary: nil, from: navigation)
        }
    }

    private func currentNavigationController() -> UINavigationController? {
        tabBarController?.selectedViewController as? UINavigationController
    }

    // MARK: - Магазин закрыт

    private func refreshStoreState() async {
        guard let state = try? await container.clientService.storeState() else {
            storeClosedController?.setRefreshing(false)
            return
        }
        if state.isOpen {
            dismissStoreClosedGate()
        } else {
            presentStoreClosedGate(state.closed)
        }
        storeClosedController?.setRefreshing(false)
    }

    private func presentStoreClosedGate(_ closure: StoreClosure?) {
        if let controller = storeClosedController, storeClosedWindow != nil {
            controller.update(closure: closure)
            return
        }
        let controller = factory.makeStoreClosed(closure: closure) { [weak self] in
            self?.requestStoreStateRefresh()
        }
        storeClosedController = controller
        storeClosedWindow = makeGateWindow(root: controller, level: GateLevel.storeClosed)
        updateKeyWindow()
        startStorePolling()
    }

    private func requestStoreStateRefresh() {
        Task { [weak self] in
            await self?.refreshStoreState()
        }
    }

    private func dismissStoreClosedGate() {
        storePollTask?.cancel()
        storePollTask = nil
        guard storeClosedWindow != nil else { return }
        dismissGateWindow(storeClosedWindow)
        storeClosedWindow = nil
        updateKeyWindow()
    }

    private func startStorePolling() {
        storePollTask?.cancel()
        storePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if Task.isCancelled { return }
                await self?.refreshStoreState()
            }
        }
    }

    // MARK: - Обновление клиента

    private func checkClientUpdate() async {
        guard !didCheckClientUpdate else { return }
        let build = container.configuration.buildNumber
        guard let version = try? await container.clientUpdate.check(build: build) else { return }
        didCheckClientUpdate = true
        let preferences = ClientUpdatePreferences(defaults: container.defaults)
        if version.mandatory || build < version.minSupportedBuild {
            presentMandatoryUpdate(version)
        } else if version.updateAvailable, version.latestBuild > build, !preferences.isDismissed(build: version.latestBuild) {
            presentOptionalUpdate(version, preferences: preferences)
        }
    }

    private func presentMandatoryUpdate(_ version: ClientVersion) {
        guard updateWindow == nil else { return }
        let controller = factory.makeClientUpdate(
            version: version,
            mandatory: true,
            onUpdate: { url in
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            },
            onLater: {}
        )
        updateWindow = makeGateWindow(root: controller, level: GateLevel.mandatoryUpdate)
        updateKeyWindow()
    }

    private func presentOptionalUpdate(_ version: ClientVersion, preferences: ClientUpdatePreferences) {
        guard let tabs = tabBarController, tabs.presentedViewController == nil else { return }
        let latestBuild = version.latestBuild
        let controller = factory.makeClientUpdate(
            version: version,
            mandatory: false,
            onUpdate: { url in
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            },
            onLater: {
                preferences.markDismissed(build: latestBuild)
            }
        )
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        tabs.present(controller, animated: true)
    }

    // MARK: - Окна-шлюзы

    private func makeGateWindow(root: UIViewController, level: CGFloat) -> UIWindow? {
        guard let scene = windowScene else { return nil }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + level)
        window.tintColor = Palette.accent
        window.rootViewController = root
        window.alpha = 0
        window.isHidden = false
        UIView.animate(withDuration: 0.25) {
            window.alpha = 1
        }
        return window
    }

    private func dismissGateWindow(_ window: UIWindow?) {
        guard let window = window else { return }
        UIView.animate(withDuration: 0.25, animations: {
            window.alpha = 0
        }, completion: { _ in
            window.isHidden = true
            window.rootViewController = nil
        })
    }

    /// Ключевым делается самое верхнее видимое окно.
    private func updateKeyWindow() {
        let ordered = [updateWindow, storeClosedWindow].compactMap { $0 }
        if let top = ordered.first {
            top.makeKey()
        } else {
            mainWindow.makeKey()
        }
    }

    // MARK: - AppRouting

    func showAppDetail(appId: String, summary: AppSummary?, from source: UIViewController) {
        let controller = factory.makeAppDetail(appId: appId, summary: summary, router: self)
        push(controller, from: source)
    }

    func showRoom(id: String, title: String?, from source: UIViewController) {
        let controller = factory.makeRoomList(source: .room(id: id, title: title), router: self)
        push(controller, from: source)
    }

    func showCategory(id: String, name: String, from source: UIViewController) {
        let controller = factory.makeRoomList(source: .category(id: id, name: name), router: self)
        push(controller, from: source)
    }

    func showVersionHistory(appId: String, appName: String, from source: UIViewController) {
        let controller = factory.makeVersionHistory(appId: appId, appName: appName)
        push(controller, from: source)
    }

    func showAccount(from source: UIViewController) {
        Task { [weak self, weak source] in
            guard let self, let source else { return }
            let auth = self.container.authService
            let signedIn = await auth.isSignedIn()
            let presenter = source.navigationController ?? source
            guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else { return }
            let sheet = self.factory.makeAccount(
                router: self,
                isSignedIn: signedIn,
                onSignIn: { [weak self] in
                    guard let self else { return }
                    self.container.push.refreshRegistration()
                    Task { await self.container.telemetry.flush() }
                },
                onSignOut: {
                    Task { await auth.signOut() }
                }
            )
            presenter.present(sheet, animated: true)
        }
    }

    func openExternal(_ url: URL, from source: UIViewController) {
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = Palette.accent
            source.present(safari, animated: true)
        } else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func push(_ controller: UIViewController, from source: UIViewController) {
        if let navigation = source as? UINavigationController {
            navigation.pushViewController(controller, animated: true)
        } else if let navigation = source.navigationController {
            navigation.pushViewController(controller, animated: true)
        } else {
            source.present(UINavigationController(rootViewController: controller), animated: true)
        }
    }
}

/// Фоновое время на отправку телеметрии при уходе в фон.
@MainActor
final class BackgroundTaskToken {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    static func begin(name: String) -> BackgroundTaskToken {
        let token = BackgroundTaskToken()
        token.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak token] in
            token?.end()
        }
        return token
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
