import UIKit

/// Витрина. Один контроллер на вкладки «Сегодня», «Игры», «Приложения»: `tab` выбирает источник.
/// Каждая серверная комната — секция `UICollectionViewCompositionalLayout` со своим section provider.
final class StorefrontViewController: UIViewController, UICollectionViewDelegate {
    enum Section: Hashable {
        case loading
        case room(String)
    }

    enum Item: Hashable {
        case skeleton(Int)
        case hero(roomId: String, index: Int, card: HeroCard)
        case row(roomId: String, app: AppSummary)
        case card(roomId: String, app: AppSummary)
        case chip(roomId: String, chip: CategoryChip)
    }

    private enum LoadState {
        case idle
        case loading
        case loaded
        case failed(APIError)
    }

    private let tab: StorefrontTab
    private let catalog: CatalogServicing
    private let live: CatalogLiveObserving
    private let installService: InstallService
    private weak var router: AppRouting?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let refreshControl = UIRefreshControl()
    private let stateView = StateView()

    private var rooms: [Room] = []
    private var roomsById: [String: Room] = [:]
    private var loadState: LoadState = .idle
    private var loadTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?

    init(
        tab: StorefrontTab,
        catalog: CatalogServicing,
        live: CatalogLiveObserving,
        installService: InstallService,
        router: AppRouting
    ) {
        self.tab = tab
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
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = makeAccountBarButton(target: self, action: #selector(openAccount))
        configureCollectionView()
        configureDataSource()
        observeLiveChanges()
        load(showsSkeleton: true)
    }

    // MARK: - Collection view

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            self?.makeSection(at: index, environment: environment)
        }
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = Spacing.s
        layout.configuration = configuration

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Palette.background
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.refreshControl = refreshControl
        collectionView.backgroundView = stateView
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        stateView.isHidden = true
        stateView.onAction = { [weak self] in
            self?.load(showsSkeleton: true)
        }
        view.addSubview(collectionView)
    }

    private func configureDataSource() {
        let rowRegistration = UICollectionView.CellRegistration<AppRowCell, AppSummary> { [weak self] cell, _, app in
            guard let self = self else { return }
            cell.configure(app: app, installService: self.installService)
            cell.onInstallTap = { [weak self] app in
                self?.handleInstall(app)
            }
        }
        let cardRegistration = UICollectionView.CellRegistration<AppCardCell, AppSummary> { [weak self] cell, _, app in
            guard let self = self else { return }
            cell.configure(app: app, installService: self.installService)
            cell.onInstallTap = { [weak self] app in
                self?.handleInstall(app)
            }
        }
        let heroRegistration = UICollectionView.CellRegistration<HeroCardCell, HeroCard> { [weak self] cell, _, card in
            guard let self = self else { return }
            cell.configure(card: card, installService: self.installService)
            cell.onInstallTap = { [weak self] app in
                self?.handleInstall(app)
            }
        }
        let chipRegistration = UICollectionView.CellRegistration<ChipCell, CategoryChip> { cell, _, chip in
            cell.configure(chip: chip)
        }
        let skeletonRegistration = UICollectionView.CellRegistration<SkeletonCell, Int> { _, _, _ in }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .skeleton(let index):
                return collectionView.dequeueConfiguredReusableCell(using: skeletonRegistration, for: indexPath, item: index)
            case .hero(_, _, let card):
                return collectionView.dequeueConfiguredReusableCell(using: heroRegistration, for: indexPath, item: card)
            case .row(_, let app):
                return collectionView.dequeueConfiguredReusableCell(using: rowRegistration, for: indexPath, item: app)
            case .card(_, let app):
                return collectionView.dequeueConfiguredReusableCell(using: cardRegistration, for: indexPath, item: app)
            case .chip(_, let chip):
                return collectionView.dequeueConfiguredReusableCell(using: chipRegistration, for: indexPath, item: chip)
            }
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<SectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let self = self,
                  let section = self.dataSource.sectionIdentifier(for: indexPath.section),
                  case .room(let roomId) = section,
                  let room = self.roomsById[roomId] else { return }
            let showsAll = room.hasMore && room.style != .chips
            header.configure(title: room.title, subtitle: room.subtitle, showsAll: showsAll)
            header.onShowAll = { [weak self] in
                guard let self = self else { return }
                self.router?.showRoom(id: room.id, title: room.title, from: self)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    // MARK: - Layout

    private func makeSection(at index: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        guard let identifier = dataSource?.sectionIdentifier(for: index) else { return nil }
        switch identifier {
        case .loading:
            return StorefrontLayout.skeletonSection()
        case .room(let roomId):
            guard let room = roomsById[roomId] else { return nil }
            let section: NSCollectionLayoutSection
            switch room.style {
            case .heroCarousel:
                section = StorefrontLayout.heroSection(environment: environment)
            case .shelfOne:
                section = StorefrontLayout.shelfOneSection(environment: environment)
            case .shelfTwo:
                section = StorefrontLayout.shelfTwoSection(environment: environment)
            case .chips:
                section = StorefrontLayout.chipsSection()
            case .unknown:
                section = StorefrontLayout.shelfOneSection(environment: environment)
            }
            if room.title != nil || (room.hasMore && room.style != .chips) {
                section.boundarySupplementaryItems = [StorefrontLayout.header()]
            }
            return section
        }
    }

    // MARK: - Данные

    @objc private func handleRefresh() {
        load(showsSkeleton: false)
    }

    private func load(showsSkeleton: Bool) {
        loadTask?.cancel()
        loadState = .loading
        if rooms.isEmpty && showsSkeleton {
            applySnapshot(animated: false)
        }
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let response = try await self.catalog.groupings(tab: self.tab)
                await self.live.noteRevision(response.revision)
                self.setRooms(response.rooms)
                self.loadState = .loaded
            } catch {
                let apiError = APIError.wrap(error)
                if apiError == .cancelled { return }
                self.loadState = .failed(apiError)
                if !self.rooms.isEmpty, self.refreshControl.isRefreshing {
                    self.presentError(apiError)
                }
            }
            self.refreshControl.endRefreshing()
            self.applySnapshot(animated: true)
        }
    }

    private func setRooms(_ newRooms: [Room]) {
        var seen = Set<String>()
        var result: [Room] = []
        for room in newRooms where !seen.contains(room.id) {
            seen.insert(room.id)
            var cleaned = room
            cleaned.items = Self.uniqueAvailable(room.items)
            cleaned.hero = room.hero.filter { $0.app.isAvailable }
            result.append(cleaned)
        }
        rooms = result
        roomsById = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
    }

    private static func uniqueAvailable(_ apps: [AppSummary]) -> [AppSummary] {
        var seen = Set<String>()
        return apps.filter { app in
            guard app.isAvailable, !seen.contains(app.id) else { return false }
            seen.insert(app.id)
            return true
        }
    }

    private func items(for room: Room) -> [Item] {
        switch room.style {
        case .heroCarousel:
            let cards = room.hero.isEmpty
                ? room.items.map { HeroCard(app: $0, headline: nil, title: nil, imageUrl: nil, gradient: nil) }
                : room.hero
            return cards.enumerated().map { Item.hero(roomId: room.id, index: $0.offset, card: $0.element) }
        case .shelfOne, .unknown:
            return room.items.map { Item.row(roomId: room.id, app: $0) }
        case .shelfTwo:
            return room.items.map { Item.card(roomId: room.id, app: $0) }
        case .chips:
            var seen = Set<String>()
            return room.categories.compactMap { chip in
                guard !seen.contains(chip.id) else { return nil }
                seen.insert(chip.id)
                return Item.chip(roomId: room.id, chip: chip)
            }
        }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if case .loading = loadState, rooms.isEmpty {
            snapshot.appendSections([.loading])
            snapshot.appendItems((0..<6).map { Item.skeleton($0) }, toSection: .loading)
        } else {
            for room in rooms {
                let roomItems = items(for: room)
                guard !roomItems.isEmpty else { continue }
                snapshot.appendSections([.room(room.id)])
                snapshot.appendItems(roomItems, toSection: .room(room.id))
            }
        }
        dataSource.apply(snapshot, animatingDifferences: animated && view.window != nil)
        updateStateView(isEmpty: snapshot.numberOfItems == 0)
    }

    private func updateStateView(isEmpty: Bool) {
        guard isEmpty else {
            stateView.isHidden = true
            return
        }
        stateView.isHidden = false
        switch loadState {
        case .failed(let error):
            stateView.show(.message(
                symbol: error.symbolName,
                title: L10n.tr("storefront.error.title"),
                message: error.userMessage,
                actionTitle: L10n.tr("common.retry")
            ))
        case .loading, .idle:
            stateView.show(.loading(L10n.tr("storefront.loading")))
        case .loaded:
            stateView.show(.message(
                symbol: "square.stack.3d.up.slash",
                title: L10n.tr("storefront.empty.title"),
                message: L10n.tr("storefront.empty.message"),
                actionTitle: L10n.tr("common.refresh")
            ))
        }
    }

    // MARK: - Живые обновления

    private func observeLiveChanges() {
        let live = self.live
        liveTask = Task { [weak self] in
            let stream = await live.subscribe()
            for await event in stream {
                guard let self = self else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: CatalogLiveEvent) {
        switch event {
        case .appRemoved(let appId):
            let updated = rooms.map { room -> Room in
                var copy = room
                copy.items.removeAll { $0.id == appId }
                copy.hero.removeAll { $0.app.id == appId }
                return copy
            }
            setRooms(updated)
            applySnapshot(animated: true)
        case .appUpserted(let app):
            let updated = rooms.map { room -> Room in
                var copy = room
                copy.items = room.items.map { $0.id == app.id ? app : $0 }
                copy.hero = room.hero.map { card in
                    card.app.id == app.id
                        ? HeroCard(app: app, headline: card.headline, title: card.title, imageUrl: card.imageUrl, gradient: card.gradient)
                        : card
                }
                return copy
            }
            setRooms(updated)
            applySnapshot(animated: true)
        case .roomsChanged, .reset:
            load(showsSkeleton: false)
        }
    }

    // MARK: - Действия

    @objc private func openAccount() {
        router?.showAccount(from: self)
    }

    private func handleInstall(_ app: AppSummary) {
        InstallPrompter.handleTap(app: app, service: installService, from: self)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .skeleton:
            break
        case .hero(_, _, let card):
            router?.showAppDetail(appId: card.app.id, summary: card.app, from: self)
        case .row(_, let app), .card(_, let app):
            router?.showAppDetail(appId: app.id, summary: app, from: self)
        case .chip(_, let chip):
            router?.showCategory(id: chip.id, name: chip.name, from: self)
        }
    }
}
