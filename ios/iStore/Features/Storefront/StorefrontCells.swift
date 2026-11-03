import UIKit

// MARK: - Hero

/// Широкая карточка hero-карусели: картинка, градиент, заголовок и приложение с кнопкой.
final class HeroCardCell: UICollectionViewCell {
    var onInstallTap: ((AppSummary) -> Void)?

    private let backgroundGradient = GradientView()
    private let imageView = RemoteImageView(frame: .zero)
    private let shade = GradientView(diagonal: false)
    private let headlineLabel = UILabel()
    private let titleLabel = UILabel()
    private let iconView = AppIconView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let installButton = InstallButton(size: .mini, prominent: true)
    private weak var installService: InstallService?
    private var app: AppSummary?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 22
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        imageView.placeholderColor = .clear
        shade.colors = [UIColor.black.withAlphaComponent(0), UIColor.black.withAlphaComponent(0.6)]

        headlineLabel.font = Typography.font(.caption1, weight: .bold)
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.textColor = UIColor.white.withAlphaComponent(0.85)

        titleLabel.font = Typography.rounded(.title2, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2

        nameLabel.font = Typography.font(.subheadline, weight: .semibold)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .white
        subtitleLabel.font = Typography.font(.caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.8)

        let topStack = UIStackView(arrangedSubviews: [headlineLabel, titleLabel])
        topStack.axis = .vertical
        topStack.spacing = Spacing.xs

        let names = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
        names.axis = .vertical
        names.spacing = 2

        installButton.setContentHuggingPriority(.required, for: .horizontal)
        installButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        installButton.onTap = { [weak self] in
            guard let self = self, let app = self.app else { return }
            self.onInstallTap?(app)
        }

        let bottomRow = UIStackView(arrangedSubviews: [iconView, names, installButton])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center
        bottomRow.spacing = Spacing.m

        [backgroundGradient, imageView, shade, topStack, bottomRow, iconView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        contentView.addSubview(backgroundGradient)
        contentView.addSubview(imageView)
        contentView.addSubview(shade)
        contentView.addSubview(topStack)
        contentView.addSubview(bottomRow)

        NSLayoutConstraint.activate([
            backgroundGradient.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundGradient.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backgroundGradient.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundGradient.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shade.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shade.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shade.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            shade.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.6),

            topStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.l),
            topStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.l),
            topStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.l),

            bottomRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.l),
            bottomRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.l),
            bottomRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Spacing.l),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44)
        ])

        isAccessibilityElement = false
        titleLabel.isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.reset()
        iconView.reset()
        installService?.removeObserver(self)
        installService = nil
        app = nil
        onInstallTap = nil
    }

    func configure(card: HeroCard, installService: InstallService) {
        app = card.app
        self.installService = installService
        let colors = (card.gradient ?? []).compactMap { UIColor(hex: $0) }
        backgroundGradient.colors = colors.count >= 2 ? colors : Palette.brandGradient
        imageView.setImage(url: card.imageUrl)
        headlineLabel.text = card.headline?.uppercased()
        headlineLabel.isHidden = card.headline == nil
        titleLabel.text = card.title ?? card.app.name
        nameLabel.text = card.app.name
        subtitleLabel.text = card.app.subtitle
        iconView.setIcon(url: card.app.iconUrl)
        installButton.accentColor = Palette.tint(light: card.app.tintLight, dark: card.app.tintDark)
        titleLabel.accessibilityLabel = [card.headline, card.title, card.app.name].compactMap { $0 }.joined(separator: ", ")

        installButton.apply(installService.state(for: card.app.id), animated: false)
        let appId = card.app.id
        installService.addObserver(self) { [weak self] changedId, state in
            guard changedId == appId else { return }
            self?.installButton.apply(state, animated: true)
        }
    }
}

// MARK: - Shelf two

/// Крупная карточка полки стиля 2 в цветах приложения.
final class AppCardCell: UICollectionViewCell {
    var onInstallTap: ((AppSummary) -> Void)?

    private let iconView = AppIconView()
    private let badgeLabel = UILabel()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let metaLabel = UILabel()
    private let installButton = InstallButton(size: .mini)
    private weak var installService: InstallService?
    private var app: AppSummary?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 22
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        badgeLabel.font = Typography.font(.caption2, weight: .bold)
        badgeLabel.adjustsFontForContentSizeCategory = true
        nameLabel.font = Typography.rounded(.title3, weight: .bold)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Palette.textPrimary
        nameLabel.numberOfLines = 2
        subtitleLabel.font = Typography.font(.subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = Palette.textSecondary
        subtitleLabel.numberOfLines = 2
        metaLabel.font = Typography.font(.caption1)
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = Palette.textSecondary

        installButton.onTap = { [weak self] in
            guard let self = self, let app = self.app else { return }
            self.onInstallTap?(app)
        }

        let textStack = UIStackView(arrangedSubviews: [badgeLabel, nameLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = Spacing.xs

        let bottomRow = UIStackView(arrangedSubviews: [metaLabel, UIView(), installButton])
        bottomRow.axis = .horizontal
        bottomRow.alignment = .center
        bottomRow.spacing = Spacing.s

        [iconView, textStack, bottomRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.l),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.l),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),

            textStack.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: Spacing.m),
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.l),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.l),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomRow.topAnchor, constant: -Spacing.s),

            bottomRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.l),
            bottomRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.l),
            bottomRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Spacing.l)
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
    }

    func configure(app: AppSummary, installService: InstallService) {
        self.app = app
        self.installService = installService
        let tint = Palette.tint(light: app.tintLight, dark: app.tintDark)
        contentView.backgroundColor = Palette.heroBackground(hex: app.bgColor, tintLight: app.tintLight)
        iconView.setIcon(url: app.iconUrl)
        nameLabel.text = app.name
        subtitleLabel.text = app.subtitle
        badgeLabel.textColor = tint
        switch app.badge {
        case .some(.new):
            badgeLabel.text = L10n.tr("badge.new").uppercased()
            badgeLabel.isHidden = false
        case .some(.updated):
            badgeLabel.text = L10n.tr("badge.updated").uppercased()
            badgeLabel.isHidden = false
        default:
            badgeLabel.text = nil
            badgeLabel.isHidden = true
        }
        var meta: [String] = []
        if let category = app.category?.name {
            meta.append(category)
        }
        if let rating = app.rating {
            meta.append("★ " + Formatters.rating(rating))
        }
        metaLabel.text = meta.joined(separator: " · ")
        installButton.accentColor = tint
        nameLabel.accessibilityLabel = [app.name, app.subtitle, metaLabel.text].compactMap { $0 }.joined(separator: ", ")

        installButton.apply(installService.state(for: app.id), animated: false)
        let appId = app.id
        installService.addObserver(self) { [weak self] changedId, state in
            guard changedId == appId else { return }
            self?.installButton.apply(state, animated: true)
        }
    }
}

// MARK: - Chips

/// Капсула категории.
final class ChipCell: UICollectionViewCell {
    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = Palette.card
        contentView.layer.cornerCurve = .continuous

        iconView.tintColor = Palette.accent
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium)
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = Typography.font(.subheadline, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.textPrimary
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Spacing.s - 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Spacing.s),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Spacing.s),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.l - 2),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Spacing.l)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.cornerRadius = contentView.bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.6 : 1 }
    }

    func configure(chip: CategoryChip) {
        let symbol = chip.sfSymbol.flatMap { UIImage(systemName: $0) } ?? UIImage(systemName: "square.grid.2x2.fill")
        iconView.image = symbol
        label.text = chip.name
        accessibilityLabel = chip.name
    }
}

// MARK: - Skeleton

/// Плейсхолдер строки на время загрузки.
final class SkeletonCell: UICollectionViewCell {
    private let icon = UIView()
    private let lineOne = UIView()
    private let lineTwo = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        [icon, lineOne, lineTwo].forEach {
            $0.backgroundColor = Palette.skeleton
            $0.layer.cornerCurve = .continuous
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        icon.layer.cornerRadius = 13
        lineOne.layer.cornerRadius = 6
        lineTwo.layer.cornerRadius = 6
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
            lineOne.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Spacing.m),
            lineOne.topAnchor.constraint(equalTo: icon.topAnchor, constant: 12),
            lineOne.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.45),
            lineOne.heightAnchor.constraint(equalToConstant: 12),
            lineTwo.leadingAnchor.constraint(equalTo: lineOne.leadingAnchor),
            lineTwo.topAnchor.constraint(equalTo: lineOne.bottomAnchor, constant: Spacing.s),
            lineTwo.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.3),
            lineTwo.heightAnchor.constraint(equalToConstant: 12)
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, contentView.layer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.isRemovedOnCompletion = false
        contentView.layer.add(pulse, forKey: "pulse")
    }
}

// MARK: - Header

/// Заголовок секции: название, подзаголовок и «Показать все».
final class SectionHeaderView: UICollectionReusableView {
    var onShowAll: (() -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let showAllButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = Typography.font(.title2, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Palette.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        subtitleLabel.font = Typography.font(.subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = Palette.textSecondary
        subtitleLabel.numberOfLines = 0

        showAllButton.setTitle(L10n.tr("storefront.show_all"), for: .normal)
        showAllButton.titleLabel?.font = Typography.font(.body)
        showAllButton.titleLabel?.adjustsFontForContentSizeCategory = true
        showAllButton.setContentHuggingPriority(.required, for: .horizontal)
        showAllButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        showAllButton.addTarget(self, action: #selector(handleShowAll), for: .touchUpInside)

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 2

        let row = UIStackView(arrangedSubviews: [labels, showAllButton])
        row.axis = .horizontal
        row.alignment = .lastBaseline
        row.spacing = Spacing.s
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let bottom = row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.s)
        bottom.priority = .init(999)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.s),
            bottom,
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xl),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xl)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onShowAll = nil
    }

    func configure(title: String?, subtitle: String?, showsAll: Bool) {
        titleLabel.text = title
        titleLabel.isHidden = title == nil
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        showAllButton.isHidden = !showsAll
    }

    @objc private func handleShowAll() {
        onShowAll?()
    }
}
