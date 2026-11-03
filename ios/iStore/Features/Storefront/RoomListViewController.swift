import UIKit

/// Источник списка «Показать все»: комната витрины или категория из чипа.
enum RoomListSource: Hashable {
    case room(id: String, title: String?)
    case category(id: String, name: String)
}

/// Полный список подборки или категории с курсорной пагинацией.
final class RoomListViewController: UIViewController, UICollectionViewDelegate {
    private enum Section: Hashable {
        case main
        case footer
    }

    private enum Item: Hashable {
        case app(AppSummary)
        case loadingMore
    }

    private let source: RoomListSource
    private let catalog: CatalogServicing
    private let live: CatalogLiveObserving
    private let installService: InstallService
    private weak var router: AppRouting?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let stateView = StateView()
    private let refreshControl = UIRefreshControl()

    private var apps: [AppSummary] = []
    private var nextCursor: String?
    private var didLoadFirstPage = false
    private var isLoading = false
    private var lastError: APIError?
    private var pageTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?

    init(
        source: RoomListSource,
        catalog: CatalogServicing,
        live: CatalogLiveObserving,
        installService: InstallService,
        router: AppRouting
    ) {
        self.source = source
        self.catalog = catalog
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
        navigationItem.largeTitleDisplayMode = .never
        switch source {
        case .room(_, let title):
            self.title = title ?? L10n.tr("room.fallback_title")
        case .category(_, let name):
            self.title = name
        }
        configureCollectionView()
        configureDataSource()
        observeLiveChanges()
        loadPage(reset: true)
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
        let appRegistration = UICollectionView.CellRegistration<AppRowCell, AppSummary> { [weak self] cell, _, app in
            guard let self = self else { return }
            cell.configure(app: app, installService: self.installService, showsMeta: true)
            cell.onInstallTap = { [weak self] app in
                guard let self = self else { return }
                InstallPrompter.handleTap(app: app, service: self.installService, from: self)
            }
        }
        let footerRegistration = UICollectionView.CellRegistration<LoadingFooterCell, Int> { cell, _, _ in
            cell.startAnimating()
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .app(let app):
                return collectionView.dequeueConfiguredReusableCell(using: appRegistration, for: indexPath, item: app)
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
        if reset && apps.isEmpty {
            stateView.isHidden = false
            stateView.show(.loading(L10n.tr("common.loading")))
        }
        let cursor = reset ? nil : nextCursor
        let source = self.source
        let catalog = self.catalog
        pageTask = Task { [weak self] in
            do {
                let page: (items: [AppSummary], next: String?, title: String?)
                switch source {
                case .room(let id, _):
                    let response = try await catalog.roomPage(id: id, cursor: cursor)
                    page = (response.items, response.nextCursor, response.room.title)
                case .category(let id, _):
                    let response = try await catalog.categoryPage(id: id, cursor: cursor)
                    page = (response.items, response.nextCursor, response.category.name)
                }
                guard let self = self else { return }
                self.apply(page: page.items, next: page.next, title: page.title, reset: reset)
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

    private func apply(page: [AppSummary], next: String?, title: String?, reset: Bool) {
        if reset {
            apps = []
        }
        var known = Set(apps.map(\.id))
        for app in page where app.isAvailable && !known.contains(app.id) {
            apps.append(app)
            known.insert(app.id)
        }
        nextCursor = next
        didLoadFirstPage = true
        isLoading = false
        if let title = title, !title.isEmpty {
            self.title = title
        }
        refreshControl.endRefreshing()
        applySnapshot()
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(apps.map { Item.app($0) }, toSection: .main)
        if nextCursor != nil && !apps.isEmpty && lastError == nil {
            snapshot.appendSections([.footer])
            snapshot.appendItems([.loadingMore], toSection: .footer)
        }
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        updateStateView()
    }

    private func updateStateView() {
        if !apps.isEmpty {
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
                symbol: "tray",
                title: L10n.tr("room.empty.title"),
                message: L10n.tr("room.empty.message"),
                actionTitle: nil
            ))
        } else {
            stateView.show(.loading(L10n.tr("common.loading")))
        }
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
                    self.apps.removeAll { $0.id == appId }
                    self.applySnapshot()
                case .appUpserted(let app):
                    self.apps = self.apps.map { $0.id == app.id ? app : $0 }
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
            if indexPath.item >= apps.count - 5 {
                loadPage(reset: false)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard case .app(let app)? = dataSource.itemIdentifier(for: indexPath) else { return }
        router?.showAppDetail(appId: app.id, summary: app, from: self)
    }
}

/// Индикатор подгрузки следующей страницы.
final class LoadingFooterCell: UICollectionViewCell {
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = false
        contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        accessibilityLabel = L10n.tr("common.loading")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimating() {
        spinner.startAnimating()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        spinner.startAnimating()
    }
}
