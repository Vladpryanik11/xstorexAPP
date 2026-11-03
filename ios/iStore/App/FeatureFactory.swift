import UIKit

/// Собирает экраны фич из зависимостей контейнера.
@MainActor
final class FeatureFactory {
    private unowned let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    // MARK: - Вкладки

    func makeStorefront(tab: StorefrontTab, router: AppRouting) -> StorefrontViewController {
        StorefrontViewController(
            tab: tab,
            catalog: container.catalogService,
            live: container.liveSync,
            installService: container.installService,
            router: router
        )
    }

    func makeManager(router: AppRouting) -> ManagerViewController {
        ManagerViewController(installService: container.installService, router: router)
    }

    func makeSearch(router: AppRouting) -> SearchViewController {
        SearchViewController(
            catalog: container.catalogService,
            installService: container.installService,
            history: SearchHistoryStore(defaults: container.defaults),
            router: router
        )
    }

    // MARK: - Каталог

    func makeAppDetail(appId: String, summary: AppSummary?, router: AppRouting) -> AppDetailViewController {
        AppDetailViewController(
            appId: appId,
            summary: summary,
            catalog: container.catalogService,
            live: container.liveSync,
            installService: container.installService,
            device: container.device,
            router: router
        )
    }

    func makeRoomList(source: RoomListSource, router: AppRouting) -> RoomListViewController {
        RoomListViewController(
            source: source,
            catalog: container.catalogService,
            live: container.liveSync,
            installService: container.installService,
            router: router
        )
    }

    func makeVersionHistory(appId: String, appName: String) -> VersionHistoryViewController {
        VersionHistoryViewController(appId: appId, appName: appName, catalog: container.catalogService)
    }

    // MARK: - Шлюзы

    func makeLaunchPlaceholder() -> LaunchPlaceholderViewController {
        LaunchPlaceholderViewController()
    }

    func makeActivation(onActivated: @escaping (Account) -> Void) -> ActivationViewController {
        ActivationViewController(auth: container.authService, onActivated: onActivated)
    }

    func makeStoreClosed(closure: StoreClosure?, onRefresh: @escaping () -> Void) -> StoreClosedViewController {
        StoreClosedViewController(closure: closure, onRefresh: onRefresh)
    }

    func makeSubscriptionRenew(
        account: Account?,
        onRecheck: @escaping @MainActor () async -> Bool
    ) -> SubscriptionRenewViewController {
        SubscriptionRenewViewController(account: account, onRecheck: onRecheck)
    }

    // MARK: - Шиты

    func makeAccount(onSignOut: @escaping () -> Void) -> UIViewController {
        let controller = AccountViewController(
            clientService: container.clientService,
            configuration: container.configuration,
            device: container.device,
            onSignOut: onSignOut
        )
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        return navigation
    }

    func makeClientUpdate(
        version: ClientVersion,
        mandatory: Bool,
        onUpdate: @escaping (URL) -> Void,
        onLater: @escaping () -> Void
    ) -> ClientUpdateViewController {
        ClientUpdateViewController(version: version, mandatory: mandatory, onUpdate: onUpdate, onLater: onLater)
    }
}
