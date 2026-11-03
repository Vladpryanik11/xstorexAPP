import UIKit

/// «Магазин закрыт»: сообщение сервера, обратный отсчёт до `reopens_at`, ссылки и «Проверить снова».
final class StoreClosedViewController: UIViewController {
    private var closure: StoreClosure?
    private let onRefresh: () -> Void

    private let gradient = BrandGradientView(dark: true)
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let returnCard = GlassBackgroundView(cornerRadius: 20)
    private let returnCaption = UILabel()
    private let returnValue = UILabel()
    private let linksStack = UIStackView()
    private let linksHint = UILabel()
    private let refreshButton = PrimaryButton(title: L10n.tr("store_closed.refresh"), fill: .white, text: Palette.brandBlue)
    private var countdownTask: Task<Void, Never>?
    private var didRequestAutoRefresh = false

    init(closure: StoreClosure?, onRefresh: @escaping () -> Void) {
        self.closure = closure
        self.onRefresh = onRefresh
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.brandDarkGradient[1]
        buildLayout()
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCountdown()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        countdownTask?.cancel()
        countdownTask = nil
    }

    func update(closure: StoreClosure?) {
        self.closure = closure
        didRequestAutoRefresh = false
        if isViewLoaded {
            render()
        }
    }

    func setRefreshing(_ refreshing: Bool) {
        refreshButton.isLoading = refreshing
    }

    // MARK: - Раскладка

    private func buildLayout() {
        gradient.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gradient)
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Spacing.l

        iconView.image = UIImage(systemName: "moon.zzz.fill")
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 52, weight: .regular)
        iconView.isAccessibilityElement = false

        titleLabel.font = Typography.rounded(.largeTitle, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header

        messageLabel.font = Typography.font(.body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        returnCaption.font = Typography.font(.footnote, weight: .semibold)
        returnCaption.adjustsFontForContentSizeCategory = true
        returnCaption.textColor = UIColor.white.withAlphaComponent(0.75)
        returnCaption.textAlignment = .center
        returnCaption.text = L10n.tr("store_closed.return_caption")
        returnValue.font = Typography.rounded(.title2, weight: .bold)
        returnValue.adjustsFontForContentSizeCategory = true
        returnValue.textColor = .white
        returnValue.textAlignment = .center
        returnValue.numberOfLines = 0

        let returnStack = UIStackView(arrangedSubviews: [returnCaption, returnValue])
        returnStack.axis = .vertical
        returnStack.spacing = Spacing.xs
        returnStack.translatesAutoresizingMaskIntoConstraints = false
        returnCard.contentView.addSubview(returnStack)
        NSLayoutConstraint.activate([
            returnStack.topAnchor.constraint(equalTo: returnCard.contentView.topAnchor, constant: Spacing.l),
            returnStack.bottomAnchor.constraint(equalTo: returnCard.contentView.bottomAnchor, constant: -Spacing.l),
            returnStack.leadingAnchor.constraint(equalTo: returnCard.contentView.leadingAnchor, constant: Spacing.l),
            returnStack.trailingAnchor.constraint(equalTo: returnCard.contentView.trailingAnchor, constant: -Spacing.l)
        ])

        linksStack.axis = .vertical
        linksStack.spacing = Spacing.s

        linksHint.font = Typography.font(.caption1)
        linksHint.adjustsFontForContentSizeCategory = true
        linksHint.textColor = UIColor.white.withAlphaComponent(0.6)
        linksHint.textAlignment = .center
        linksHint.numberOfLines = 0
        linksHint.text = L10n.tr("store_closed.links_hint")

        refreshButton.addTarget(self, action: #selector(handleRefresh), for: .touchUpInside)

        [iconView, titleLabel, messageLabel, returnCard, linksStack, linksHint, refreshButton].forEach {
            stack.addArrangedSubview($0)
        }
        stack.setCustomSpacing(Spacing.xl, after: messageLabel)
        stack.setCustomSpacing(Spacing.xl, after: linksHint)

        NSLayoutConstraint.activate([
            gradient.topAnchor.constraint(equalTo: view.topAnchor),
            gradient.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gradient.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 80),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Spacing.xxl),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.leadingAnchor, constant: Spacing.xl),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -Spacing.xl)
        ])
        let preferredWidth = stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -Spacing.xl * 2)
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
    }

    // MARK: - Содержимое

    private func render() {
        titleLabel.text = closure?.title ?? L10n.tr("store_closed.fallback_title")
        messageLabel.text = closure?.message ?? L10n.tr("store_closed.fallback_message")
        renderLinks()
        updateCountdown()
    }

    private func renderLinks() {
        linksStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let links = closure?.links ?? []
        for (index, link) in links.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(link.title, for: .normal)
            button.setImage(UIImage(systemName: "arrow.up.right.square"), for: .normal)
            button.semanticContentAttribute = .forceRightToLeft
            button.tintColor = .white
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = Typography.font(.body, weight: .semibold)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
            button.layer.cornerRadius = 12
            button.layer.cornerCurve = .continuous
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            button.tag = index
            button.accessibilityHint = L10n.tr("store_closed.links_hint")
            button.addTarget(self, action: #selector(handleLink(_:)), for: .touchUpInside)
            linksStack.addArrangedSubview(button)
        }
        linksStack.isHidden = links.isEmpty
        linksHint.isHidden = links.isEmpty
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let controller = self else { return }
                controller.updateCountdown()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func updateCountdown() {
        guard let reopensAt = closure?.reopensAt else {
            returnValue.text = L10n.tr("store_closed.back_soon")
            return
        }
        if let remaining = Formatters.countdown(to: reopensAt) {
            returnValue.text = L10n.tr("store_closed.back_in_format", remaining)
            returnValue.accessibilityLabel = L10n.tr("store_closed.back_at_format", Formatters.time(reopensAt))
        } else {
            returnValue.text = L10n.tr("store_closed.back_soon")
            if !didRequestAutoRefresh {
                didRequestAutoRefresh = true
                onRefresh()
            }
        }
    }

    // MARK: - Действия

    @objc private func handleRefresh() {
        refreshButton.isLoading = true
        onRefresh()
    }

    @objc private func handleLink(_ sender: UIButton) {
        let links = closure?.links ?? []
        guard links.indices.contains(sender.tag) else { return }
        UIApplication.shared.open(links[sender.tag].url, options: [:], completionHandler: nil)
    }
}
