import UIKit

/// Строка приложения: иконка, имя, подзаголовок, мини-кнопка установки.
/// Используется в полке стиля 1, на экранах «Показать все» и в результатах поиска.
final class AppRowCell: UICollectionViewCell {
    static let reuseIdentifier = "AppRowCell"

    var onInstallTap: ((AppSummary) -> Void)?

    /// Действия VoiceOver для строки (дублируют контекстное меню).
    var rowAccessibilityActions: [UIAccessibilityCustomAction]? {
        didSet { nameLabel.accessibilityCustomActions = rowAccessibilityActions }
    }

    private let iconView = AppIconView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let metaLabel = UILabel()
    private let installButton = InstallButton(size: .mini)
    private let separator = UIView()
    private weak var installService: InstallService?
    private var app: AppSummary?

    var showsSeparator: Bool = true {
        didSet { separator.isHidden = !showsSeparator }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = Typography.font(.body, weight: .medium)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Palette.textPrimary
        nameLabel.numberOfLines = 1

        subtitleLabel.font = Typography.font(.footnote)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = Palette.textSecondary
        subtitleLabel.numberOfLines = 1

        metaLabel.font = Typography.font(.caption2)
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = Palette.textTertiary
        metaLabel.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel, metaLabel])
        labels.axis = .vertical
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.setContentHuggingPriority(.required, for: .horizontal)
        installButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        installButton.onTap = { [weak self] in
            guard let self = self, let app = self.app else { return }
            self.onInstallTap?(app)
        }

        separator.backgroundColor = Palette.separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(iconView)
        contentView.addSubview(labels)
        contentView.addSubview(installButton)
        contentView.addSubview(separator)

        let iconSize: CGFloat = 60
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.s),
            iconView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Spacing.s),

            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Spacing.m),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: Spacing.s),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Spacing.s),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: installButton.leadingAnchor, constant: -Spacing.m),

            installButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            installButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: labels.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        isAccessibilityElement = false
        nameLabel.isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.reset()
        installService?.removeObserver(self)
        installService = nil
        app = nil
        onInstallTap = nil
        rowAccessibilityActions = nil
        installButton.apply(.idle, animated: false)
    }

    /// `note` заменяет строку метаданных, например «Уведомления выключены».
    func configure(app: AppSummary, installService: InstallService, showsMeta: Bool = false, note: String? = nil) {
        self.app = app
        self.installService = installService
        iconView.setIcon(url: app.iconUrl)
        nameLabel.text = app.name
        subtitleLabel.text = app.subtitle ?? app.category?.name
        subtitleLabel.isHidden = subtitleLabel.text == nil

        if let note = note {
            metaLabel.text = note
            metaLabel.isHidden = false
        } else if showsMeta {
            var parts: [String] = []
            if let rating = app.rating {
                parts.append("★ " + Formatters.rating(rating))
            }
            parts.append(Formatters.bytes(app.sizeBytes))
            metaLabel.text = parts.joined(separator: " · ")
            metaLabel.isHidden = false
        } else {
            metaLabel.isHidden = true
        }

        nameLabel.accessibilityLabel = [app.name, subtitleLabel.text, note].compactMap { $0 }.joined(separator: ", ")
        installButton.apply(installService.state(for: app.id), animated: false)
        let appId = app.id
        installService.addObserver(self) { [weak self] changedId, state in
            guard changedId == appId else { return }
            self?.installButton.apply(state, animated: true)
        }
    }
}
