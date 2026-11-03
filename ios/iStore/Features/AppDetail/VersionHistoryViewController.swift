import UIKit

/// История версий приложения с пагинацией.
final class VersionHistoryViewController: UITableViewController {
    private let appId: String
    private let appName: String
    private let catalog: CatalogServicing

    private var versions: [AppVersion] = []
    private var nextCursor: String?
    private var didLoadFirstPage = false
    private var isLoading = false
    private var lastError: APIError?
    private let stateView = StateView()
    private let footerSpinner = UIActivityIndicatorView(style: .medium)

    init(appId: String, appName: String, catalog: CatalogServicing) {
        self.appId = appId
        self.appName = appName
        self.catalog = catalog
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.tr("versions.title")
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "version")
        tableView.backgroundView = stateView
        footerSpinner.frame = CGRect(x: 0, y: 0, width: 44, height: 56)
        stateView.onAction = { [weak self] in
            self?.loadNextPage()
        }
        loadNextPage()
    }

    private func loadNextPage() {
        guard !isLoading else { return }
        if didLoadFirstPage && nextCursor == nil { return }
        isLoading = true
        lastError = nil
        if versions.isEmpty {
            stateView.isHidden = false
            stateView.show(.loading(L10n.tr("common.loading")))
        } else {
            footerSpinner.startAnimating()
            tableView.tableFooterView = footerSpinner
        }
        let catalog = self.catalog
        let appId = self.appId
        let cursor = nextCursor
        Task { [weak self] in
            do {
                let page = try await catalog.versions(appId: appId, cursor: cursor)
                guard let self = self else { return }
                self.versions.append(contentsOf: page.items)
                self.nextCursor = page.nextCursor
                self.didLoadFirstPage = true
                self.finishLoading()
            } catch {
                guard let self = self else { return }
                self.lastError = APIError.wrap(error)
                self.finishLoading()
            }
        }
    }

    private func finishLoading() {
        isLoading = false
        footerSpinner.stopAnimating()
        tableView.tableFooterView = nil
        tableView.reloadData()
        if !versions.isEmpty {
            stateView.isHidden = true
        } else if let error = lastError {
            stateView.isHidden = false
            stateView.show(.message(
                symbol: error.symbolName,
                title: error.userTitle,
                message: error.userMessage,
                actionTitle: L10n.tr("common.retry")
            ))
        } else {
            stateView.isHidden = false
            stateView.show(.message(
                symbol: "clock.arrow.circlepath",
                title: L10n.tr("versions.empty.title"),
                message: L10n.tr("versions.empty.message_format", appName),
                actionTitle: nil
            ))
        }
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        versions.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "version", for: indexPath)
        let version = versions[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        var title = L10n.tr("detail.version_format", version.version)
        if let build = version.build, !build.isEmpty {
            title += " (\(build))"
        }
        content.text = title
        content.textProperties.font = Typography.font(.headline, weight: .semibold)
        var lines: [String] = []
        var meta: [String] = []
        if let date = version.releasedAt {
            meta.append(Formatters.date(date))
        }
        if let size = version.sizeBytes {
            meta.append(Formatters.bytes(size))
        }
        if !meta.isEmpty {
            lines.append(meta.joined(separator: " · "))
        }
        if let notes = version.notes, !notes.isEmpty {
            lines.append(notes)
        }
        content.secondaryText = lines.joined(separator: "\n")
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = Palette.textSecondary
        content.textToSecondaryTextVerticalPadding = Spacing.xs
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= versions.count - 3 {
            loadNextPage()
        }
    }
}
