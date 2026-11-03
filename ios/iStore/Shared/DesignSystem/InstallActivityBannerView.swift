import UIKit

/// Стеклянный баннер активности установки над таб-баром.
final class InstallActivityBannerView: UIView {
    var onTap: (() -> Void)?
    var onClose: (() -> Void)?

    private let glass = GlassBackgroundView(cornerRadius: 22)
    private let iconView = AppIconView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let indicator = InstallButton(size: .mini)
    private let closeButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)

        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = Typography.font(.subheadline, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Palette.textPrimary
        statusLabel.font = Typography.font(.caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = Palette.textSecondary

        let labels = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        labels.axis = .vertical
        labels.spacing = 2

        indicator.isUserInteractionEnabled = false
        indicator.setContentHuggingPriority(.required, for: .horizontal)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = Palette.textTertiary
        closeButton.accessibilityLabel = L10n.tr("common.close")
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [iconView, labels, indicator, closeButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(row)

        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
            row.topAnchor.constraint(equalTo: glass.contentView.topAnchor, constant: Spacing.s),
            row.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor, constant: -Spacing.s),
            row.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor, constant: Spacing.m),
            row.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor, constant: -Spacing.m)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isAccessibilityElement = false
        accessibilityElements = [titleLabel, closeButton]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(app: AppSummary, state: InstallState, extraCount: Int) {
        iconView.setIcon(url: app.iconUrl)
        titleLabel.text = extraCount > 0
            ? L10n.tr("install.banner.title_more", app.name, extraCount)
            : app.name
        statusLabel.text = InstallStatusText.text(for: state)
        indicator.apply(state, animated: true)
        titleLabel.accessibilityLabel = [titleLabel.text, statusLabel.text].compactMap { $0 }.joined(separator: ", ")
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleClose() {
        onClose?()
    }
}

/// Тексты статусов установки «что происходит».
enum InstallStatusText {
    static func text(for state: InstallState) -> String {
        switch state {
        case .idle: return L10n.tr("install.status.idle")
        case .preparing: return L10n.tr("install.status.preparing")
        case .ready: return L10n.tr("install.status.ready")
        case .handingOff: return L10n.tr("install.status.handing_off")
        case .installing: return L10n.tr("install.status.installing")
        case .failed(let code): return InstallErrorText.title(for: code)
        }
    }
}

/// Ошибки установки по схеме «что случилось + что сделать» (01 §8.2).
enum InstallErrorText {
    static func title(for code: String) -> String {
        L10n.tr(key(for: code) + ".title")
    }

    static func message(for code: String) -> String {
        L10n.tr(key(for: code) + ".message")
    }

    private static func key(for code: String) -> String {
        switch code {
        case InstallErrorCode.offline, "transport_-1009":
            return "install.error.offline"
        case InstallErrorCode.timedOut, "timed_out", "server_job_expired", "install_token_expired":
            return "install.error.expired"
        case InstallErrorCode.appNotAvailable, "not_found":
            return "install.error.unavailable"
        case InstallErrorCode.noBuild, "no_build_available":
            return "install.error.no_build"
        case InstallErrorCode.accountInactive:
            return "install.error.account_inactive"
        case InstallErrorCode.installURLMissing:
            return "install.error.url_missing"
        case InstallErrorCode.launchFailed:
            return "install.error.launch_failed"
        case InstallErrorCode.incompatibleDevice:
            return "install.error.incompatible"
        case InstallErrorCode.insufficientSpace:
            return "install.error.space"
        default:
            return "install.error.generic"
        }
    }
}
