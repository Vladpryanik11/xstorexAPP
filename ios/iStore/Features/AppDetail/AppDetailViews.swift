import UIKit

// MARK: - Hero header

/// Шапка карточки в цветах приложения: иконка, имя, подзаголовок, кнопка установки.
final class AppDetailHeaderView: UIView {
    let installButton = InstallButton(size: .regular, prominent: true)

    private let iconView = AppIconView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let developerLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = Typography.rounded(.title1, weight: .bold)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 0
        nameLabel.textColor = Palette.textPrimary
        nameLabel.accessibilityTraits = .header

        subtitleLabel.font = Typography.font(.subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2
        subtitleLabel.textColor = Palette.textSecondary

        developerLabel.font = Typography.font(.footnote)
        developerLabel.adjustsFontForContentSizeCategory = true
        developerLabel.textColor = Palette.textTertiary

        badgeLabel.font = Typography.font(.caption2, weight: .bold)
        badgeLabel.adjustsFontForContentSizeCategory = true

        installButton.setContentHuggingPriority(.required, for: .horizontal)
        let buttonRow = UIStackView(arrangedSubviews: [installButton, UIView()])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [badgeLabel, nameLabel, subtitleLabel, developerLabel, buttonRow])
        textStack.axis = .vertical
        textStack.spacing = Spacing.xs
        textStack.setCustomSpacing(Spacing.m, after: developerLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.xl),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xl),
            iconView.widthAnchor.constraint(equalToConstant: 118),
            iconView.heightAnchor.constraint(equalToConstant: 118),
            iconView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Spacing.xl),

            textStack.topAnchor.constraint(equalTo: iconView.topAnchor),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Spacing.l),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xl),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Spacing.xl)
        ])
        // Высота шапки — минимальная, при которой помещаются иконка и тексты.
        let collapse = heightAnchor.constraint(equalToConstant: 0)
        collapse.priority = .defaultLow
        collapse.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(summary: AppSummary, developer: String?) {
        let tint = Palette.tint(light: summary.tintLight, dark: summary.tintDark)
        backgroundColor = Palette.heroBackground(hex: summary.bgColor, tintLight: summary.tintLight)
        iconView.setIcon(url: summary.iconUrl)
        nameLabel.text = summary.name
        subtitleLabel.text = summary.subtitle
        subtitleLabel.isHidden = summary.subtitle == nil
        developerLabel.text = developer
        developerLabel.isHidden = developer == nil
        installButton.accentColor = tint
        badgeLabel.textColor = tint
        switch summary.badge {
        case .some(.new):
            badgeLabel.text = L10n.tr("badge.new").uppercased()
            badgeLabel.isHidden = false
        case .some(.updated):
            badgeLabel.text = L10n.tr("badge.updated").uppercased()
            badgeLabel.isHidden = false
        default:
            badgeLabel.isHidden = true
        }
    }
}

// MARK: - Stats strip

/// Полоса статистики: рейтинг, возраст, размер, категория.
final class AppDetailStatsView: UIView {
    struct Stat {
        let caption: String
        let value: String
        let detail: String?
    }

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Spacing.m),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Spacing.m),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Spacing.s),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Spacing.s),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -Spacing.m * 2)
        ])
        let widthAtLeast = stack.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -Spacing.s * 2)
        widthAtLeast.isActive = true
        stack.distribution = .fillEqually
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(stats: [Stat]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, stat) in stats.enumerated() {
            let column = makeColumn(stat)
            if index > 0 {
                let line = UIView()
                line.backgroundColor = Palette.separator
                line.translatesAutoresizingMaskIntoConstraints = false
                column.addSubview(line)
                NSLayoutConstraint.activate([
                    line.leadingAnchor.constraint(equalTo: column.leadingAnchor),
                    line.widthAnchor.constraint(equalToConstant: 0.5),
                    line.topAnchor.constraint(equalTo: column.topAnchor, constant: Spacing.s),
                    line.bottomAnchor.constraint(equalTo: column.bottomAnchor, constant: -Spacing.s)
                ])
            }
            stack.addArrangedSubview(column)
        }
    }

    private func makeColumn(_ stat: Stat) -> UIView {
        let caption = UILabel()
        caption.text = stat.caption.uppercased()
        caption.font = Typography.font(.caption2, weight: .semibold)
        caption.adjustsFontForContentSizeCategory = true
        caption.textColor = Palette.textTertiary
        caption.textAlignment = .center

        let value = UILabel()
        value.text = stat.value
        value.font = Typography.rounded(.title3, weight: .bold)
        value.adjustsFontForContentSizeCategory = true
        value.textColor = Palette.textSecondary
        value.textAlignment = .center
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.6

        let detail = UILabel()
        detail.text = stat.detail
        detail.font = Typography.font(.caption2)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = Palette.textTertiary
        detail.textAlignment = .center
        detail.isHidden = stat.detail == nil

        let column = UIStackView(arrangedSubviews: [caption, value, detail])
        column.axis = .vertical
        column.spacing = 2
        column.alignment = .center
        column.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: container.topAnchor),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Spacing.m),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Spacing.m),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
        container.isAccessibilityElement = true
        container.accessibilityLabel = [stat.caption, stat.value, stat.detail].compactMap { $0 }.joined(separator: ", ")
        return container
    }
}

// MARK: - Screenshots

/// Горизонтальная лента скриншотов.
final class ScreenshotsRowView: UIView {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var heightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.decelerationRate = .fast
        stack.axis = .horizontal
        stack.spacing = Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stack)
        let height = scrollView.heightAnchor.constraint(equalToConstant: 420)
        heightConstraint = height
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            height,
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Spacing.xl),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Spacing.xl),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(screenshots: [Screenshot], height: CGFloat) {
        heightConstraint?.constant = height
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, shot) in screenshots.enumerated() {
            let imageView = RemoteImageView(frame: .zero)
            imageView.layer.cornerRadius = 18
            imageView.layer.cornerCurve = .continuous
            imageView.layer.borderWidth = 0.5
            imageView.layer.borderColor = Palette.separator.cgColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            let ratio = shot.height > 0 ? CGFloat(shot.width) / CGFloat(shot.height) : 0.46
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: max(0.3, min(ratio, 2.2))).isActive = true
            imageView.setImage(url: shot.url)
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = L10n.tr("detail.screenshot_format", index + 1, screenshots.count)
            stack.addArrangedSubview(imageView)
        }
    }
}

// MARK: - Text sections

/// Заголовок секции карточки с необязательной кнопкой справа.
final class DetailSectionTitleView: UIView {
    let actionButton = UIButton(type: .system)
    private let titleLabel = UILabel()

    init(title: String, actionTitle: String? = nil) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = Typography.font(.title3, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.accessibilityTraits = .header
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.titleLabel?.font = Typography.font(.body)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.isHidden = actionTitle == nil
        actionButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [titleLabel, actionButton])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = Spacing.s
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.xl),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.s),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xl),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xl)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Текст, свёрнутый до нескольких строк, с кнопкой «ещё».
final class ExpandableTextView: UIView {
    private let label = UILabel()
    private let moreButton = UIButton(type: .system)
    private let collapsedLines: Int
    private var isExpanded = false
    var onToggle: (() -> Void)?

    init(collapsedLines: Int = 3) {
        self.collapsedLines = collapsedLines
        super.init(frame: .zero)
        label.font = Typography.font(.body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.textPrimary
        label.numberOfLines = collapsedLines
        label.translatesAutoresizingMaskIntoConstraints = false

        moreButton.setTitle(L10n.tr("detail.more"), for: .normal)
        moreButton.titleLabel?.font = Typography.font(.body, weight: .semibold)
        moreButton.titleLabel?.adjustsFontForContentSizeCategory = true
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)

        addSubview(label)
        addSubview(moreButton)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xl),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xl),
            moreButton.topAnchor.constraint(equalTo: label.bottomAnchor),
            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xl),
            moreButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String? {
        get { label.text }
        set {
            label.text = newValue
            isExpanded = false
            label.numberOfLines = collapsedLines
            let lineCount = newValue?.components(separatedBy: "\n").count ?? 0
            let long = (newValue?.count ?? 0) > 140 || lineCount > collapsedLines
            moreButton.isHidden = !long
        }
    }

    @objc private func toggle() {
        isExpanded.toggle()
        label.numberOfLines = isExpanded ? 0 : collapsedLines
        moreButton.setTitle(L10n.tr(isExpanded ? "detail.less" : "detail.more"), for: .normal)
        onToggle?()
    }
}

/// Строка «название — значение» в блоке «Информация».
final class InfoRowView: UIView {
    init(label: String, value: String) {
        super.init(frame: .zero)
        let left = UILabel()
        left.text = label
        left.font = Typography.font(.subheadline)
        left.adjustsFontForContentSizeCategory = true
        left.textColor = Palette.textSecondary
        left.setContentHuggingPriority(.required, for: .horizontal)
        left.setContentCompressionResistancePriority(.required, for: .horizontal)

        let right = UILabel()
        right.text = value
        right.font = Typography.font(.subheadline)
        right.adjustsFontForContentSizeCategory = true
        right.textColor = Palette.textPrimary
        right.textAlignment = .right
        right.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [left, right])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = Spacing.l
        row.translatesAutoresizingMaskIntoConstraints = false

        let line = UIView()
        line.backgroundColor = Palette.separator
        line.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)
        addSubview(line)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.m),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.m),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xl),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xl),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xl),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xl),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "\(label), \(value)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Similar

/// Плитка похожего приложения.
final class SimilarAppTile: UIControl {
    let app: AppSummary

    init(app: AppSummary) {
        self.app = app
        super.init(frame: .zero)
        let icon = AppIconView()
        icon.isUserInteractionEnabled = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setIcon(url: app.iconUrl)

        let name = UILabel()
        name.text = app.name
        name.font = Typography.font(.footnote, weight: .medium)
        name.adjustsFontForContentSizeCategory = true
        name.numberOfLines = 2
        name.textColor = Palette.textPrimary

        let category = UILabel()
        category.text = app.category?.name
        category.font = Typography.font(.caption2)
        category.adjustsFontForContentSizeCategory = true
        category.textColor = Palette.textSecondary

        let stack = UIStackView(arrangedSubviews: [icon, name, category])
        stack.axis = .vertical
        stack.spacing = Spacing.xs
        stack.alignment = .leading
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 80),
            icon.heightAnchor.constraint(equalToConstant: 80),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: 96)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [app.name, app.category?.name].compactMap { $0 }.joined(separator: ", ")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}
