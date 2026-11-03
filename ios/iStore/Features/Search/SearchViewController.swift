import UIKit

/// Поиск: история, подсказки с задержкой 250 мс, результаты с пагинацией,
/// пустое состояние с «Запросить приложение».
final class SearchViewController: UIViewController, UICollectionViewDelegate, UISearchResultsUpdating, UISearchBarDelegate {
    private enum Section: Hashable {
        case history
        case hints
        case corrected
        case results
        case footer
    }

    private enum Item: Hashable {
        case history(String)
        case clearHistory
        case hint(SearchHint)
        case corrected(String)
        case app(AppSummary)
        case loadingMore
    }

    private enum Mode {
        case idle
        case typing
        case results
    }

    static let hintsDebounceNanoseconds: UInt64 = 250_000_000

    private let catalog: CatalogServicing
    private let installService: InstallService
    private let history: SearchHistoryStore
    private weak var router: AppRouting?

    private let searchController = UISearchController(searchResultsController: nil)
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let stateView = StateView()

    private var mode: Mode = .idle
    private var hints: [SearchHint] = []
    private var results: [AppSummary] = []
    private var submittedQuery: String?
    private var correctedQuery: String?
    private var nextCursor: String?
    private var isSearching = false
    private var searchError: APIError?
    private var hintsTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(catalog: CatalogServicing, installService: InstallService, history: SearchHistoryStore, router: AppRouting) {
        self.catalog = catalog
        self.installService = installService
        self.history = history
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
        navigationItem.rightBarButtonItem = makeAccountBarButton(target: self, action: #selector(openAccount))
        configureSearchController()
        configureCollectionView()
        configureDataSource()
        applySnapshot()
    }

    // MARK: - Настройка

    private func configureSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = L10n.tr("search.placeholder")
        searchController.searchBar.delegate = self
        searchController.searchBar.autocapitalizationType = .none
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func configureCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self = self, let section = self.dataSource?.sectionIdentifier(for: index) else { return nil }
            switch section {
            case .results:
                return StorefrontLayout.listSection(environment: environment)
            case .footer:
                return StorefrontLayout.skeletonSection()
            case .history, .hints, .corrected:
                var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                configuration.showsSeparators = section != .corrected
                configuration.backgroundColor = .clear
                return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            }
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = Palette.background
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delegate = self
        collectionView.backgroundView = stateView
        view.addSubview(collectionView)
    }

    private func configureDataSource() {
        let textRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = UIListContentConfiguration.cell()
            content.textProperties.font = Typography.font(.body)
            switch item {
            case .history(let text):
                content.text = text
                content.image = UIImage(systemName: "clock.arrow.circlepath")
                content.imageProperties.tintColor = Palette.textTertiary
            case .clearHistory:
                content.text = L10n.tr("search.history.clear")
                content.textProperties.color = Palette.accent
            case .hint(let hint):
                content.text = hint.text
                content.image = UIImage(systemName: hint.appId == nil ? "magnifyingglass" : "app")
                content.imageProperties.tintColor = Palette.textTertiary
            case .corrected(let text):
                content.text = L10n.tr("search.corrected_format", text)
                content.textProperties.color = Palette.textSecondary
                content.textProperties.font = Typography.font(.footnote)
            case .app, .loadingMore:
                break
            }
            cell.contentConfiguration = content
        }
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
            default:
                return collectionView.dequeueConfiguredReusableCell(using: textRegistration, for: indexPath, item: item)
            }
        }
    }

    // MARK: - Снимок

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        switch mode {
        case .idle:
            let items = history.items
            if !items.isEmpty {
                snapshot.appendSections([.history])
                snapshot.appendItems(items.map { Item.history($0) } + [.clearHistory], toSection: .history)
            }
        case .typing:
            if !hints.isEmpty {
                snapshot.appendSections([.hints])
                var seen = Set<SearchHint>()
                let unique = hints.filter { seen.insert($0).inserted }
                snapshot.appendItems(unique.map { Item.hint($0) }, toSection: .hints)
            }
        case .results:
            if let corrected = correctedQuery, !results.isEmpty {
                snapshot.appendSections([.corrected])
                snapshot.appendItems([.corrected(corrected)], toSection: .corrected)
            }
            if !results.isEmpty {
                snapshot.appendSections([.results])
                snapshot.appendItems(results.map { Item.app($0) }, toSection: .results)
                if nextCursor != nil && searchError == nil {
                    snapshot.appendSections([.footer])
                    snapshot.appendItems([.loadingMore], toSection: .footer)
                }
            }
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        updateStateView(isEmpty: snapshot.numberOfItems == 0)
    }

    private func updateStateView(isEmpty: Bool) {
        stateView.isHidden = !isEmpty
        guard isEmpty else { return }
        stateView.onAction = nil
        switch mode {
        case .idle, .typing:
            stateView.show(.message(
                symbol: "magnifyingglass",
                title: L10n.tr("search.idle.title"),
                message: L10n.tr("search.idle.message"),
                actionTitle: nil
            ))
        case .results:
            if isSearching {
                stateView.show(.loading(L10n.tr("search.loading")))
            } else if let error = searchError {
                stateView.show(.message(
                    symbol: error.symbolName,
                    title: L10n.tr("search.error.title"),
                    message: error.userMessage,
                    actionTitle: L10n.tr("common.retry")
                ))
                stateView.onAction = { [weak self] in
                    guard let self = self, let query = self.submittedQuery else { return }
                    self.submit(query)
                }
            } else {
                let query = submittedQuery ?? ""
                stateView.show(.message(
                    symbol: "questionmark.app.dashed",
                    title: L10n.tr("search.empty.title_format", query),
                    message: L10n.tr("search.empty.message"),
                    actionTitle: L10n.tr("search.request_format", query)
                ))
                stateView.onAction = { [weak self] in
                    self?.requestApp(query)
                }
            }
        }
    }

    // MARK: - Ввод

    func updateSearchResults(for searchController: UISearchController) {
        let text = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            hintsTask?.cancel()
            searchTask?.cancel()
            mode = .idle
            hints = []
            results = []
            submittedQuery = nil
            applySnapshot()
            return
        }
        if mode == .results, text == submittedQuery {
            return
        }
        mode = .typing
        scheduleHints(for: text)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchBar.resignFirstResponder()
        submit(text)
    }

    private func scheduleHints(for text: String) {
        hintsTask?.cancel()
        let catalog = self.catalog
        hintsTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.hintsDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            let hints = (try? await catalog.hints(query: text)) ?? []
            guard !Task.isCancelled, let self = self, self.mode == .typing else { return }
            self.hints = Array(hints.prefix(8))
            self.applySnapshot()
        }
    }

    private func submit(_ query: String) {
        hintsTask?.cancel()
        searchTask?.cancel()
        history.add(query)
        mode = .results
        submittedQuery = query
        correctedQuery = nil
        results = []
        nextCursor = nil
        searchError = nil
        isSearching = true
        if searchController.searchBar.text != query {
            searchController.searchBar.text = query
        }
        applySnapshot()
        loadResults(query: query, cursor: nil)
    }

    private func loadResults(query: String, cursor: String?) {
        let catalog = self.catalog
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                let response = try await catalog.search(query: query, cursor: cursor)
                guard !Task.isCancelled, let self = self, self.submittedQuery == query else { return }
                var known = Set(self.results.map(\.id))
                for app in response.items where app.isAvailable && !known.contains(app.id) {
                    self.results.append(app)
                    known.insert(app.id)
                }
                self.correctedQuery = response.correctedQuery
                self.nextCursor = response.nextCursor
                self.isSearching = false
                self.applySnapshot()
            } catch {
                let apiError = APIError.wrap(error)
                guard apiError != .cancelled, let self = self, self.submittedQuery == query else { return }
                self.isSearching = false
                self.searchError = apiError
                self.applySnapshot()
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard mode == .results, !isSearching, searchError == nil,
              let cursor = nextCursor, let query = submittedQuery else { return }
        loadResults(query: query, cursor: cursor)
    }

    private func requestApp(_ query: String) {
        let catalog = self.catalog
        Task { [weak self] in
            do {
                try await catalog.requestApp(query: query, note: nil)
                self?.presentErrorAlert(
                    title: L10n.tr("search.request.sent.title"),
                    message: L10n.tr("search.request.sent.message")
                )
            } catch {
                self?.presentError(error)
            }
        }
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .history(let text):
            submit(text)
        case .clearHistory:
            history.clear()
            applySnapshot()
        case .hint(let hint):
            if let appId = hint.appId {
                history.add(hint.text)
                router?.showAppDetail(appId: appId, summary: nil, from: self)
            } else {
                submit(hint.text)
            }
        case .app(let app):
            router?.showAppDetail(appId: app.id, summary: app, from: self)
        case .corrected, .loadingMore:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .loadingMore:
            loadMoreIfNeeded()
        case .app:
            if indexPath.item >= results.count - 5 {
                loadMoreIfNeeded()
            }
        default:
            break
        }
    }

    @objc private func openAccount() {
        router?.showAccount(from: self)
    }
}
