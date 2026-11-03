import UIKit

/// Пять вкладок: Сегодня, Игры, Приложения, Менеджер, Поиск. Над таб-баром — баннер активности установки.
final class MainTabBarController: UITabBarController {
    private let factory: FeatureFactory
    private weak var router: AppRouting?
    private let installService: InstallService

    private let banner = InstallActivityBannerView()
    private var bannerBottom: NSLayoutConstraint?
    private var bannerAppId: String?
    private var dismissedBannerAppIds: Set<String> = []
    private var lastAnnouncedState: InstallState?

    init(factory: FeatureFactory, router: AppRouting, installService: InstallService) {
        self.factory = factory
        self.router = router
        self.installService = installService
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.tintColor = Palette.accent
        setViewControllers(makeTabs(), animated: false)
        setUpBanner()
        installService.addObserver(self) { [weak self] _, _ in
            self?.refreshBanner()
        }
        refreshBanner()
    }

    private func makeTabs() -> [UIViewController] {
        guard let router = router else { return [] }
        let tabs: [(UIViewController, String, String)] = [
            (factory.makeStorefront(tab: .today, router: router), "tab.today", "star.square.fill"),
            (factory.makeStorefront(tab: .games, router: router), "tab.games", "gamecontroller.fill"),
            (factory.makeStorefront(tab: .apps, router: router), "tab.apps", "square.stack.3d.up.fill"),
            (factory.makeManager(router: router), "tab.manager", "arrow.down.circle.fill"),
            (factory.makeSearch(router: router), "tab.search", "magnifyingglass")
        ]
        return tabs.map { entry in
            let (controller, titleKey, symbol) = entry
            let title = L10n.tr(titleKey)
            controller.title = title
            let navigation = UINavigationController(rootViewController: controller)
            navigation.navigationBar.prefersLargeTitles = true
            navigation.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
            return navigation
        }
    }

    // MARK: - Баннер

    private func setUpBanner() {
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.isHidden = true
        banner.alpha = 0
        view.addSubview(banner)
        let bottom = banner.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -90)
        bannerBottom = bottom
        let preferredWidth = banner.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -Spacing.l * 2)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            bottom,
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            preferredWidth,
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        ])
        banner.onClose = { [weak self] in
            guard let self = self, let appId = self.bannerAppId else { return }
            self.dismissedBannerAppIds.insert(appId)
            self.refreshBanner()
        }
        banner.onTap = { [weak self] in
            guard let self = self,
                  let appId = self.bannerAppId,
                  let navigation = self.selectedViewController as? UINavigationController else { return }
            let summary = self.installService.activeInstalls.first { $0.app.id == appId }?.app
            self.router?.showAppDetail(appId: appId, summary: summary, from: navigation)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let tabBarIsAtBottom = !tabBar.isHidden && tabBar.frame.minY > view.bounds.midY
        let offset: CGFloat
        if tabBarIsAtBottom {
            offset = view.bounds.maxY - tabBar.frame.minY + Spacing.s
        } else {
            offset = view.safeAreaInsets.bottom + Spacing.s
        }
        if bannerBottom?.constant != -offset {
            bannerBottom?.constant = -offset
        }
        view.bringSubviewToFront(banner)
    }

    private func refreshBanner() {
        let activities = installService.activeInstalls
        dismissedBannerAppIds = dismissedBannerAppIds.filter { id in activities.contains { $0.app.id == id } }
        let visible = activities.filter { !dismissedBannerAppIds.contains($0.app.id) }
        guard let latest = visible.last else {
            bannerAppId = nil
            lastAnnouncedState = nil
            setBannerVisible(false)
            return
        }
        bannerAppId = latest.app.id
        banner.configure(app: latest.app, state: latest.state, extraCount: visible.count - 1)
        setBannerVisible(true)
        if lastAnnouncedState != latest.state {
            lastAnnouncedState = latest.state
            UIAccessibility.post(
                notification: .announcement,
                argument: L10n.tr("install.announcement_format", latest.app.name, InstallStatusText.text(for: latest.state))
            )
        }
    }

    private func setBannerVisible(_ visible: Bool) {
        guard visible == banner.isHidden else { return }
        if visible {
            banner.isHidden = false
            banner.transform = CGAffineTransform(translationX: 0, y: 20)
        }
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.banner.alpha = visible ? 1 : 0
            self.banner.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 20)
        } completion: { _ in
            if !visible {
                self.banner.isHidden = true
            }
        }
    }
}
