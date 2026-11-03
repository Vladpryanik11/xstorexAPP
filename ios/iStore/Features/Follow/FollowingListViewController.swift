import UIKit

/// «Отслеживаемые»: приложения, за обновлениями которых следит аккаунт. Открывается из аккаунта.
/// Долгое нажатие на строку — выключить или включить уведомления, перестать следить.
final class FollowingListViewController: UIViewController, UICollectionViewDelegate {
    private enum Section: Hashable {
        case main
        case footer
    }

    private enum Item: Hashable {
        case app(FollowedApp)
        case loadingMore
    }

    private let follows: FollowServicing
    private let live: CatalogLiveObserving
    private let installService: InstallService
    private weak var router: AppRouting?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let stateView = StateView()
    private let refreshControl = UIRefreshControl()

    private var items: [FollowedApp] = []
    private var nextCursor: String?
    private var didLoadFirstPage = false
    private var isLoading = false
    private var lastError: APIError?
    /// Пользователь мог поменять подписку в карточке: после возврата список перечитывается.
    private var reloadOnAppear = false
    private var pageTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?

    init(
        follows: FollowServicing,
        live: CatalogLiveObserving,
        installService: InstallService,
        router: AppRouting
    ) {
        self.follows = follows
        self.live = live
        self.installService = installService
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        title = L10n.tr("following.title")
        navigationItem.largeTitleDisplayMode = .never
        configureCollectionView()
        configureDataSource()
        observeLiveChanges()
        loadPage(reset: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if reloadOnAppear {
            reloadOnAppear = false
            loadPage(reset: true)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            liveTask?.cancel()
            pageTask?.cancel()
        }
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self = self, let section = self.dataSource?.sectionIdentifier(for: index) else { return nil }
            switch section {
            case .main:
                return StorefrontLayout.listSection(environment: environment)
            case .footer:
                return StorefrontLayout.skeletonSection()
            }
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Palette.background
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundView = stateView
        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        stateView.onAction = { [weak self] in
            self?.loadPage(reset: true)
        }
        view.addSubview(collectionView)
    }

    private func configureDataSource() {
        let appRegistration = UICollectionView.CellRegistration<AppRowCell, FollowedApp> { [weak self] cell, _, followed in
            guard let self = self else { return }
            cell.configure(
                app: followed.app,
                installService: self.installService,
                note: followed.muted ? L10n.tr("follow.muted_note") : nil
            )
            cell.onInstallTap = { [weak self] app in
                guard let self = self else { return }
                InstallPrompter.handleTap(app: app, service: self.installService, from: self)
            }
            cell.rowAccessibilityActions = self.makeActions(for: followed).map { action in
                UIAccessibilityCustomAction(name: action.title) { _ in
                    action.handler()
                    return true
                }
            }
        }
        let footerRegistration = UICollectionView.CellRegistration<LoadingFooterCell, Int> { cell, _, _ in
            cell.startAnimating()
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .app(let followed):
                return collectionView.dequeueConfiguredReusableCell(using: appRegistration, for: indexPath, item: followed)
            case .loadingMore:
                return collectionView.dequeueConfiguredReusableCell(using: footerRegistration, for: indexPath, item: 0)
            }
        }
    }

    // MARK: - Пагинация

    @objc private func handleRefresh() {
        loadPage(reset: true)
    }

    private func loadPage(reset: Bool) {
        if reset {
            pageTask?.cancel()
            isLoading = false
        }
        guard !isLoading else { return }
        if !reset && nextCursor == nil { return }
        isLoading = true
        lastError = nil
        if reset && items.isEmpty {
            stateView.isHidden = false
            stateView.show(.loading(L10n.tr("common.loading")))
        }
        let cursor = reset ? nil : nextCursor
        let follows = self.follows
        pageTask = Task { [weak self] in
            do {
                let page = try await follows.followedApps(cursor: cursor)
                self?.apply(page: page.items, next: page.nextCursor, reset: reset)
            } catch {
                guard let self = self else { return }
                let apiError = APIError.wrap(error)
                guard apiError != .cancelled else { return }
                self.isLoading = false
                self.lastError = apiError
                self.refreshControl.endRefreshing()
                self.applySnapshot()
            }
        }
    }

    private func apply(page: [FollowedApp], next: String?, reset: Bool) {
        if reset {
            items = []
        }
        var known = Set(items.map(\.app.id))
        for followed in page where !known.contains(followed.app.id) {
            items.append(followed)
            known.insert(followed.app.id)
        }
        nextCursor = next
        didLoadFirstPage = true
        isLoading = false
        refreshControl.endRefreshing()
        applySnapshot()
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items.map { Item.app($0) }, toSection: .main)
        if nextCursor != nil && !items.isEmpty && lastError == nil {
            snapshot.appendSections([.footer])
            snapshot.appendItems([.loadingMore], toSection: .footer)
        }
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        updateStateView()
    }

    private func updateStateView() {
        if !items.isEmpty {
            stateView.isHidden = true
            return
        }
        stateView.isHidden = false
        if let error = lastError {
            stateView.show(.message(
                symbol: error.symbolName,
                title: error.userTitle,
                message: error.userMessage,
                actionTitle: L10n.tr("common.retry")
            ))
        } else if didLoadFirstPage {
            stateView.show(.message(
                symbol: "bell",
                title: L10n.tr("following.empty.title"),
                message: L10n.tr("following.empty.message"),
                actionTitle: nil
            ))
        } else {
            stateView.show(.loading(L10n.tr("common.loading")))
        }
    }

    // MARK: - Подписка

    private struct RowAction {
        let title: String
        let symbol: String
        let destructive: Bool
        let handler: () -> Void
    }

    private func makeActions(for followed: FollowedApp) -> [RowAction] {
        let appId = followed.app.id
        let muted = followed.muted
        return [
            RowAction(
                title: L10n.tr(muted ? "follow.unmute" : "follow.mute"),
                symbol: muted ? "bell" : "bell.slash",
                destructive: false
            ) { [weak self] in
                self?.change { follows in try await follows.setMuted(!muted, appId: appId) }
            },
            RowAction(title: L10n.tr("follow.unfollow"), symbol: "minus.circle", destructive: true) { [weak self] in
                self?.change { follows in try await follows.unfollow(appId: appId) }
            }
        ]
    }

    private func change(_ operation: @escaping @Sendable (FollowServicing) async throws -> FollowStatus) {
        let follows = self.follows
        Task { [weak self] in
            do {
                let status = try await operation(follows)
                self?.applyStatus(status)
            } catch {
                guard let self = self else { return }
                let apiError = APIError.wrap(error)
                // На `account_inactive` APIClient уже открыл окно продления.
                if apiError != .accountInactive {
                    self.presentError(apiError)
                }
            }
        }
    }

    private func applyStatus(_ status: FollowStatus) {
        if status.following {
            items = items.map { followed in
                guard followed.app.id == status.appId else { return followed }
                return FollowedApp(app: followed.app, muted: status.muted, followedAt: followed.followedAt)
            }
        } else {
            items.removeAll { $0.app.id == status.appId }
        }
        applySnapshot()
    }

    // MARK: - Живые обновления

    private func observeLiveChanges() {
        let live = self.live
        liveTask = Task { [weak self] in
            let stream = await live.subscribe()
            for await event in stream {
                guard let self = self else { return }
                switch event {
                case .appRemoved(let appId):
                    self.items.removeAll { $0.app.id == appId }
                    self.applySnapshot()
                case .appUpserted(let app):
                    self.items = self.items.map { followed in
                        guard followed.app.id == app.id else { return followed }
                        return FollowedApp(app: app, muted: followed.muted, followedAt: followed.followedAt)
                    }
                    self.applySnapshot()
                case .roomsChanged, .reset:
                    break
                }
            }
        }
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .loadingMore:
            loadPage(reset: false)
        case .app:
            if indexPath.item >= items.count - 5 {
                loadPage(reset: false)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard case .app(let followed)? = dataSource.itemIdentifier(for: indexPath) else { return }
        reloadOnAppear = true
        router?.showAppDetail(appId: followed.app.id, summary: followed.app, from: self)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard case .app(let followed)? = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let actions = makeActions(for: followed).map { action in
            UIAction(
                title: action.title,
                image: UIImage(systemName: action.symbol),
                attributes: action.destructive ? .destructive : []
            ) { _ in
                action.handler()
            }
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(title: followed.app.name, children: actions)
        }
    }
}
