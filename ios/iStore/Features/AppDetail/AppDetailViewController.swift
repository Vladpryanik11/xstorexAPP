import UIKit

/// Карточка приложения: hero-шапка в цветах приложения, статистика, скриншоты, описание,
/// «Что нового», информация, история версий и похожие.
final class AppDetailViewController: UIViewController {
    private let appId: String
    private var summary: AppSummary?
    private var detail: CatalogApp?
    private let catalog: CatalogServicing
    private let follows: FollowServicing
    private let live: CatalogLiveObserving
    private let installService: InstallService
    private let device: DeviceInfo
    private weak var router: AppRouting?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let header = AppDetailHeaderView()
    private let stats = AppDetailStatsView()
    private let compatibilityLabel = UILabel()
    private let screenshots = ScreenshotsRowView()
    private let descriptionText = ExpandableTextView()
    private let whatsNewTitle = DetailSectionTitleView(
        title: L10n.tr("detail.whats_new"),
        actionTitle: L10n.tr("detail.version_history")
    )
    private let whatsNewMeta = UILabel()
    private let whatsNewText = ExpandableTextView()
    private let infoStack = UIStackView()
    private let similarScroll = UIScrollView()
    private let similarStack = UIStackView()
    private let stateView = StateView()
    private var detailSections: [UIView] = []
    private var followStatus: FollowStatus?
    private var isUpdatingFollow = false

    private var loadTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?

    init(
        appId: String,
        summary: AppSummary?,
        catalog: CatalogServicing,
        follows: FollowServicing,
        live: CatalogLiveObserving,
        installService: InstallService,
        device: DeviceInfo,
        router: AppRouting
    ) {
        self.appId = appId
        self.summary = summary
        self.catalog = catalog
        self.follows = follows
        self.live = live
        self.installService = installService
        self.device = device
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
        buildLayout()
        if let summary = summary {
            renderSummary(summary)
        }
        bindInstallButton()
        observeLiveChanges()
        load()
        loadFollowStatus()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true {
            liveTask?.cancel()
            loadTask?.cancel()
            followTask?.cancel()
            installService.removeObserver(self)
        }
    }

    // MARK: - Раскладка

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        stateView.translatesAutoresizingMaskIntoConstraints = false
        stateView.isHidden = true
        stateView.onAction = { [weak self] in
            self?.load()
        }
        view.addSubview(stateView)

        let preferredWidth = stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Spacing.xxl * 2),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: Spacing.maxContentWidth),
            preferredWidth,

            stateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 220),
            stateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        header.layer.cornerRadius = 0
        stack.addArrangedSubview(header)

        compatibilityLabel.font = Typography.font(.footnote)
        compatibilityLabel.adjustsFontForContentSizeCategory = true
        compatibilityLabel.numberOfLines = 0
        compatibilityLabel.textColor = Palette.textSecondary

        whatsNewMeta.font = Typography.font(.footnote)
        whatsNewMeta.adjustsFontForContentSizeCategory = true
        whatsNewMeta.textColor = Palette.textSecondary
        whatsNewTitle.actionButton.addTarget(self, action: #selector(openVersionHistory), for: .touchUpInside)

        infoStack.axis = .vertical

        similarScroll.showsHorizontalScrollIndicator = false
        similarScroll.translatesAutoresizingMaskIntoConstraints = false
        similarStack.axis = .horizontal
        similarStack.spacing = Spacing.l
        similarStack.alignment = .top
        similarStack.translatesAutoresizingMaskIntoConstraints = false
        similarScroll.addSubview(similarStack)
        stats.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            similarScroll.heightAnchor.constraint(equalToConstant: 150),
            stats.heightAnchor.constraint(equalToConstant: min(UIFontMetrics.default.scaledValue(for: 92), 150)),
            similarStack.topAnchor.constraint(equalTo: similarScroll.contentLayoutGuide.topAnchor),
            similarStack.bottomAnchor.constraint(equalTo: similarScroll.contentLayoutGuide.bottomAnchor),
            similarStack.leadingAnchor.constraint(equalTo: similarScroll.contentLayoutGuide.leadingAnchor, constant: Spacing.xl),
            similarStack.trailingAnchor.constraint(equalTo: similarScroll.contentLayoutGuide.trailingAnchor, constant: -Spacing.xl),
            similarStack.heightAnchor.constraint(equalTo: similarScroll.frameLayoutGuide.heightAnchor)
        ])
    }

    private func padded(_ content: UIView, top: CGFloat = 0, bottom: CGFloat = 0) -> UIView {
        let container = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: top),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottom),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Spacing.xl),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Spacing.xl)
        ])
        return container
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = Palette.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return padded(line)
    }

    // MARK: - Отрисовка

    private func renderSummary(_ summary: AppSummary) {
        title = summary.name
        header.configure(summary: summary, developer: detail?.developer)
        view.tintColor = Palette.tint(light: summary.tintLight, dark: summary.tintDark)
        navigationController?.navigationBar.tintColor = view.tintColor
    }

    private func renderDetail(_ app: CatalogApp) {
        detail = app
        summary = app.summary
        renderSummary(app.summary)
        stateView.isHidden = true

        detailSections.forEach { $0.removeFromSuperview() }
        detailSections = []
        func add(_ section: UIView) {
            stack.addArrangedSubview(section)
            detailSections.append(section)
        }

        stats.configure(stats: makeStats(app))
        add(stats)
        add(separator())

        compatibilityLabel.text = compatibilityText(for: app.summary)
        compatibilityLabel.textColor = isCompatible(app.summary) ? Palette.textSecondary : Palette.destructive
        add(padded(compatibilityLabel, top: Spacing.m, bottom: Spacing.m))

        if !app.screenshots.isEmpty {
            let wide = view.bounds.width >= 700
            screenshots.configure(screenshots: app.screenshots, height: wide ? 480 : 420)
            add(spacer(Spacing.s))
            add(screenshots)
        }

        if !app.descriptionText.isEmpty {
            descriptionText.text = app.descriptionText
            add(spacer(Spacing.xl))
            add(descriptionText)
        }

        if app.whatsNew != nil || app.updatedAt != nil {
            add(whatsNewTitle)
            var meta = [L10n.tr("detail.version_format", app.summary.version)]
            if let updated = app.updatedAt {
                meta.append(Formatters.relative(updated))
            }
            whatsNewMeta.text = meta.joined(separator: " · ")
            add(padded(whatsNewMeta, bottom: Spacing.s))
            if let notes = app.whatsNew, !notes.isEmpty {
                whatsNewText.text = notes
                add(whatsNewText)
            }
        }

        add(DetailSectionTitleView(title: L10n.tr("detail.information")))
        infoStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in makeInfoRows(app) {
            infoStack.addArrangedSubview(InfoRowView(label: row.label, value: row.value))
        }
        add(infoStack)

        let similar = app.similar.filter { $0.isAvailable && $0.id != app.id }
        if !similar.isEmpty {
            add(DetailSectionTitleView(title: L10n.tr("detail.similar")))
            similarStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for item in similar {
                let tile = SimilarAppTile(app: item)
                tile.addTarget(self, action: #selector(openSimilar(_:)), for: .touchUpInside)
                similarStack.addArrangedSubview(tile)
            }
            add(similarScroll)
        }
        refreshInstallButton()
    }

    private func makeStats(_ app: CatalogApp) -> [AppDetailStatsView.Stat] {
        var result: [AppDetailStatsView.Stat] = []
        let summary = app.summary
        if let rating = summary.rating {
            let count = summary.ratingCount.map { L10n.tr("detail.stats.ratings_format", Formatters.compactNumber($0)) }
            result.append(.init(caption: L10n.tr("detail.stats.rating"), value: Formatters.rating(rating), detail: count ?? Formatters.stars(rating)))
        }
        if let age = app.ageRating {
            result.append(.init(caption: L10n.tr("detail.stats.age"), value: age, detail: L10n.tr("detail.stats.years")))
        }
        result.append(.init(caption: L10n.tr("detail.stats.size"), value: Formatters.bytes(summary.sizeBytes), detail: nil))
        if let category = summary.category?.name {
            result.append(.init(caption: L10n.tr("detail.stats.category"), value: category, detail: nil))
        }
        if let languages = app.languages.first {
            let extra = app.languages.count > 1 ? L10n.tr("detail.stats.languages_more_format", app.languages.count - 1) : nil
            result.append(.init(caption: L10n.tr("detail.stats.language"), value: languages, detail: extra))
        }
        return result
    }

    private func makeInfoRows(_ app: CatalogApp) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let developer = app.developer {
            rows.append(InfoRow(label: L10n.tr("detail.info.developer"), value: developer))
        }
        rows.append(InfoRow(label: L10n.tr("detail.info.size"), value: Formatters.bytes(app.summary.sizeBytes)))
        if let category = app.summary.category?.name {
            rows.append(InfoRow(label: L10n.tr("detail.info.category"), value: category))
        }
        rows.append(InfoRow(
            label: L10n.tr("detail.info.compatibility"),
            value: L10n.tr("detail.requires_ios_format", app.summary.minOs)
        ))
        if !app.languages.isEmpty {
            rows.append(InfoRow(label: L10n.tr("detail.info.languages"), value: app.languages.joined(separator: ", ")))
        }
        if let age = app.ageRating {
            rows.append(InfoRow(label: L10n.tr("detail.info.age"), value: age))
        }
        rows.append(InfoRow(label: L10n.tr("detail.info.version"), value: app.summary.version))
        if let released = app.releasedAt {
            rows.append(InfoRow(label: L10n.tr("detail.info.released"), value: Formatters.date(released)))
        }
        if let bundleId = app.bundleId {
            rows.append(InfoRow(label: L10n.tr("detail.info.bundle_id"), value: bundleId))
        }
        let known = Set(rows.map(\.label))
        rows.append(contentsOf: app.info.filter { !known.contains($0.label) })
        return rows
    }

    private func isCompatible(_ app: AppSummary) -> Bool {
        OSVersion.isSatisfied(current: device.osVersion, required: app.minOs)
    }

    private func compatibilityText(for app: AppSummary) -> String {
        if isCompatible(app) {
            return L10n.tr("detail.works_on_device")
        }
        return L10n.tr("detail.requires_ios_format", app.minOs)
    }

    // MARK: - Установка

    private func bindInstallButton() {
        header.installButton.onTap = { [weak self] in
            guard let self = self, let app = self.summary else { return }
            InstallPrompter.handleTap(app: app, service: self.installService, from: self)
        }
        let appId = self.appId
        installService.addObserver(self) { [weak self] changedId, state in
            guard changedId == appId else { return }
            self?.header.installButton.apply(state, animated: true)
        }
        refreshInstallButton()
    }

    private func refreshInstallButton() {
        header.installButton.apply(installService.state(for: appId), animated: false)
        header.installButton.isEnabled = summary?.isAvailable ?? false
        header.installButton.alpha = header.installButton.isEnabled ? 1 : 0.4
    }

    // MARK: - Загрузка

    private func load() {
        loadTask?.cancel()
        if detail == nil {
            stateView.isHidden = false
            stateView.show(.loading(summary == nil ? L10n.tr("common.loading") : nil))
        }
        let catalog = self.catalog
        let appId = self.appId
        loadTask = Task { [weak self] in
            do {
                let app = try await catalog.app(id: appId)
                self?.renderDetail(app)
            } catch {
                let apiError = APIError.wrap(error)
                guard apiError != .cancelled else { return }
                self?.showLoadError(apiError)
            }
        }
    }

    private func showLoadError(_ error: APIError) {
        if case .notFound = error {
            showUnavailable()
            return
        }
        guard detail == nil else { return }
        stateView.isHidden = false
        stateView.show(.message(
            symbol: error.symbolName,
            title: L10n.tr("detail.error.title"),
            message: error.userMessage,
            actionTitle: L10n.tr("common.retry")
        ))
    }

    private func showUnavailable() {
        detailSections.forEach { $0.removeFromSuperview() }
        detailSections = []
        header.installButton.isEnabled = false
        header.installButton.alpha = 0.4
        followStatus = nil
        updateFollowButton()
        stateView.isHidden = false
        stateView.show(.message(
            symbol: "xmark.app",
            title: L10n.tr("detail.unavailable.title"),
            message: L10n.tr("detail.unavailable.message"),
            actionTitle: nil
        ))
    }

    private func observeLiveChanges() {
        let live = self.live
        let appId = self.appId
        liveTask = Task { [weak self] in
            let stream = await live.subscribe()
            for await event in stream {
                guard let self = self else { return }
                switch event {
                case .appRemoved(let removedId) where removedId == appId:
                    self.installService.cancel(appId: appId)
                    self.showUnavailable()
                case .appUpserted(let app) where app.id == appId:
                    self.load()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Подписка на обновления

    private func loadFollowStatus() {
        followTask?.cancel()
        let follows = self.follows
        let appId = self.appId
        followTask = Task { [weak self] in
            // Без статуса кнопка остаётся скрытой: ошибку загрузки карточка покажет сама.
            guard let status = try? await follows.status(appId: appId) else { return }
            self?.followStatus = status
            self?.updateFollowButton()
        }
    }

    /// Колокольчик в навбаре: без подписки — «Следить», с подпиской — меню с уведомлениями и отпиской.
    private func updateFollowButton() {
        guard let status = followStatus else {
            navigationItem.rightBarButtonItem = nil
            return
        }
        let item: UIBarButtonItem
        if status.following {
            let muted = status.muted
            let toggleMute = UIAction(
                title: L10n.tr(muted ? "follow.unmute" : "follow.mute"),
                image: UIImage(systemName: muted ? "bell" : "bell.slash")
            ) { [weak self] _ in
                self?.changeFollow { follows, appId in try await follows.setMuted(!muted, appId: appId) }
            }
            let unfollow = UIAction(
                title: L10n.tr("follow.unfollow"),
                image: UIImage(systemName: "minus.circle"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.changeFollow { follows, appId in try await follows.unfollow(appId: appId) }
            }
            item = UIBarButtonItem(
                image: muted ? UIImage(systemName: "bell.slash.fill") : UIImage(systemName: "bell.fill"),
                style: .plain,
                target: nil,
                action: nil
            )
            item.menu = UIMenu(
                title: L10n.tr(muted ? "follow.muted_note" : "follow.following_note"),
                children: [toggleMute, unfollow]
            )
            item.accessibilityLabel = L10n.tr("follow.following")
            item.accessibilityValue = muted ? L10n.tr("follow.muted_note") : nil
        } else {
            item = UIBarButtonItem(
                image: UIImage(systemName: "bell"),
                style: .plain,
                target: self,
                action: #selector(followTapped)
            )
            item.accessibilityLabel = L10n.tr("follow.follow")
        }
        item.isEnabled = !isUpdatingFollow
        navigationItem.rightBarButtonItem = item
    }

    @objc private func followTapped() {
        changeFollow { follows, appId in try await follows.follow(appId: appId) }
    }

    private func changeFollow(_ operation: @escaping @Sendable (FollowServicing, String) async throws -> FollowStatus) {
        guard !isUpdatingFollow else { return }
        isUpdatingFollow = true
        updateFollowButton()
        let follows = self.follows
        let appId = self.appId
        let wasFollowing = followStatus?.following ?? false
        Task { [weak self] in
            do {
                let status = try await operation(follows, appId)
                guard let self = self else { return }
                if status.following && !wasFollowing {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                self.isUpdatingFollow = false
                self.followStatus = status
                self.updateFollowButton()
            } catch {
                guard let self = self else { return }
                self.isUpdatingFollow = false
                self.updateFollowButton()
                let apiError = APIError.wrap(error)
                // На `account_inactive` APIClient уже открыл окно продления.
                if apiError != .accountInactive {
                    self.presentError(apiError)
                }
            }
        }
    }

    // MARK: - Действия

    @objc private func openVersionHistory() {
        router?.showVersionHistory(appId: appId, appName: summary?.name ?? "", from: self)
    }

    @objc private func openSimilar(_ sender: SimilarAppTile) {
        router?.showAppDetail(appId: sender.app.id, summary: sender.app, from: self)
    }
}
