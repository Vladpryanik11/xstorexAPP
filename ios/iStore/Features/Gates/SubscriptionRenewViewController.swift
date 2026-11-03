import SafariServices
import UIKit

/// «Подписка закончилась»: «Продлить» открывает оплату, «Я продлил» перепроверяет профиль.
final class SubscriptionRenewViewController: UIViewController {
    private var account: Account?
    private let onRecheck: @MainActor () async -> Bool

    private let gradient = BrandGradientView()
    private let card = UIView()
    private let mark = BrandMarkView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let planLabel = UILabel()
    private let statusLabel = UILabel()
    private let renewButton = PrimaryButton(title: L10n.tr("subscription.renew"))
    private let recheckButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var isChecking = false

    init(account: Account?, onRecheck: @escaping @MainActor () async -> Bool) {
        self.account = account
        self.onRecheck = onRecheck
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.brandBlue
        buildLayout()
        render()
    }

    func update(account: Account?) {
        self.account = account
        if isViewLoaded {
            render()
        }
    }

    private func buildLayout() {
        [gradient, card, mark].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(gradient)
        view.addSubview(card)

        card.backgroundColor = Palette.elevatedCard
        card.layer.cornerRadius = 28
        card.layer.cornerCurve = .continuous

        let markHolder = UIView()
        markHolder.addSubview(mark)

        titleLabel.text = L10n.tr("subscription.title")
        titleLabel.font = Typography.rounded(.title1, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        messageLabel.text = L10n.tr("subscription.message")
        messageLabel.font = Typography.font(.body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = Palette.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        planLabel.font = Typography.font(.footnote, weight: .semibold)
        planLabel.adjustsFontForContentSizeCategory = true
        planLabel.textColor = Palette.textTertiary
        planLabel.textAlignment = .center
        planLabel.numberOfLines = 0

        statusLabel.font = Typography.font(.footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = Palette.textSecondary
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        renewButton.addTarget(self, action: #selector(handleRenew), for: .touchUpInside)

        recheckButton.setTitle(L10n.tr("subscription.recheck"), for: .normal)
        recheckButton.titleLabel?.font = Typography.font(.body, weight: .semibold)
        recheckButton.titleLabel?.adjustsFontForContentSizeCategory = true
        recheckButton.addTarget(self, action: #selector(handleRecheck), for: .touchUpInside)

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            markHolder, titleLabel, messageLabel, planLabel, renewButton, recheckButton, spinner, statusLabel
        ])
        stack.axis = .vertical
        stack.spacing = Spacing.l
        stack.setCustomSpacing(Spacing.s, after: titleLabel)
        stack.setCustomSpacing(Spacing.xl, after: planLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let preferredWidth = card.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -Spacing.xl * 2)
        preferredWidth.priority = .defaultHigh
        let centerY = card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        centerY.priority = .defaultHigh

        NSLayoutConstraint.activate([
            gradient.topAnchor.constraint(equalTo: view.topAnchor),
            gradient.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gradient.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerY,
            preferredWidth,
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: Spacing.l),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: Spacing.xxl),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Spacing.xl),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Spacing.xl),

            mark.widthAnchor.constraint(equalToConstant: 64),
            mark.heightAnchor.constraint(equalToConstant: 64),
            mark.topAnchor.constraint(equalTo: markHolder.topAnchor),
            mark.bottomAnchor.constraint(equalTo: markHolder.bottomAnchor),
            mark.centerXAnchor.constraint(equalTo: markHolder.centerXAnchor)
        ])
    }

    private func render() {
        var parts: [String] = []
        if let plan = account?.plan {
            parts.append(plan.name)
        }
        if let expiresAt = account?.expiresAt {
            parts.append(L10n.tr("subscription.expired_on_format", Formatters.date(expiresAt)))
        }
        planLabel.text = parts.joined(separator: " · ")
        planLabel.isHidden = parts.isEmpty
        renewButton.isHidden = account?.renewUrl == nil
        if account?.status == .suspended {
            messageLabel.text = L10n.tr("subscription.message_suspended")
        } else {
            messageLabel.text = L10n.tr("subscription.message")
        }
    }

    @objc private func handleRenew() {
        guard let url = account?.renewUrl else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = Palette.accent
        safari.dismissButtonStyle = .close
        present(safari, animated: true)
    }

    @objc private func handleRecheck() {
        guard !isChecking else { return }
        isChecking = true
        recheckButton.isEnabled = false
        statusLabel.isHidden = true
        spinner.startAnimating()
        Task { [weak self] in
            guard let self = self else { return }
            let isActive = await self.onRecheck()
            self.isChecking = false
            self.recheckButton.isEnabled = true
            self.spinner.stopAnimating()
            if !isActive {
                self.statusLabel.text = L10n.tr("subscription.still_inactive")
                self.statusLabel.isHidden = false
                UIAccessibility.post(notification: .announcement, argument: self.statusLabel.text)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }
}
