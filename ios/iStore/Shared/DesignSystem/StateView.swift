import UIKit

/// Заглушка состояния экрана: загрузка, ошибка с «Повторить», пустота.
/// Своя реализация, потому что `UIContentUnavailableConfiguration` есть только с iOS 17.
final class StateView: UIView {
    enum Content {
        case loading(String?)
        case message(symbol: String, title: String, message: String?, actionTitle: String?)
    }

    var onAction: (() -> Void)?

    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = Palette.textTertiary
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)

        titleLabel.font = Typography.font(.title3, weight: .semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.textColor = Palette.textPrimary

        messageLabel.font = Typography.font(.subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.textColor = Palette.textSecondary

        actionButton.titleLabel?.font = Typography.font(.body, weight: .semibold)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)

        spinner.hidesWhenStopped = true

        [spinner, iconView, titleLabel, messageLabel, actionButton].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(Spacing.l, after: messageLabel)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Spacing.xxl),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Spacing.xxl),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ content: Content) {
        switch content {
        case .loading(let text):
            spinner.startAnimating()
            iconView.isHidden = true
            titleLabel.isHidden = true
            messageLabel.text = text
            messageLabel.isHidden = text == nil
            actionButton.isHidden = true
            accessibilityLabel = text
        case let .message(symbol, title, message, actionTitle):
            spinner.stopAnimating()
            iconView.image = UIImage(systemName: symbol)
            iconView.isHidden = false
            titleLabel.text = title
            titleLabel.isHidden = false
            messageLabel.text = message
            messageLabel.isHidden = message == nil
            actionButton.setTitle(actionTitle, for: .normal)
            actionButton.isHidden = actionTitle == nil
        }
    }

    @objc private func handleAction() {
        onAction?()
    }
}

/// Основная кнопка-капсула со спиннером загрузки.
final class PrimaryButton: UIButton {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var storedTitle: String?
    private var fillColor: UIColor
    private var textColor: UIColor

    init(title: String, fill: UIColor = Palette.accent, text: UIColor = .white) {
        fillColor = fill
        textColor = text
        super.init(frame: .zero)
        storedTitle = title
        setTitle(title, for: .normal)
        setTitleColor(text, for: .normal)
        setTitleColor(text.withAlphaComponent(0.6), for: .disabled)
        titleLabel?.font = Typography.font(.headline, weight: .semibold)
        titleLabel?.adjustsFontForContentSizeCategory = true
        backgroundColor = fill
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        spinner.color = text
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isLoading: Bool = false {
        didSet {
            isEnabled = !isLoading
            if isLoading {
                setTitle(nil, for: .normal)
                spinner.startAnimating()
            } else {
                setTitle(storedTitle, for: .normal)
                spinner.stopAnimating()
            }
        }
    }

    func setPrimaryTitle(_ title: String) {
        storedTitle = title
        if !isLoading {
            setTitle(title, for: .normal)
        }
    }

    override var isEnabled: Bool {
        didSet { updateFill() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.75 : 1 }
    }

    private func updateFill() {
        backgroundColor = isEnabled || isLoading ? fillColor : fillColor.withAlphaComponent(0.45)
    }
}
