import UIKit

/// Вход по коду активации: «два шага, и каталог ваш».
final class ActivationViewController: UIViewController, UITextFieldDelegate {
    private let auth: AuthServicing
    private let onActivated: (Account) -> Void

    private let gradient = BrandGradientView()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let card = UIView()
    private let mark = BrandMarkView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let codeField = UITextField()
    private let errorLabel = UILabel()
    private let submitButton = PrimaryButton(title: L10n.tr("activation.submit"))
    private let hintLabel = UILabel()
    private var isSubmitting = false

    init(auth: AuthServicing, onActivated: @escaping (Account) -> Void) {
        self.auth = auth
        self.onActivated = onActivated
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
        configureContent()
        updateSubmitState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if codeField.text?.isEmpty ?? true {
            codeField.becomeFirstResponder()
        }
    }

    // MARK: - Раскладка

    private func buildLayout() {
        [gradient, scrollView, contentView, card, mark].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(gradient)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(card)
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive

        card.backgroundColor = Palette.elevatedCard
        card.layer.cornerRadius = 28
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 30
        card.layer.shadowOffset = CGSize(width: 0, height: 12)

        let steps = UIStackView(arrangedSubviews: [
            makeStepRow(number: 1, text: L10n.tr("activation.step1")),
            makeStepRow(number: 2, text: L10n.tr("activation.step2"))
        ])
        steps.axis = .vertical
        steps.spacing = Spacing.m

        // Знак по центру: обёртка внутри `.fill`-стека.
        let markHolder = UIView()
        markHolder.addSubview(mark)

        let stack = UIStackView(arrangedSubviews: [
            markHolder, titleLabel, subtitleLabel, steps, codeField, errorLabel, submitButton, hintLabel
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Spacing.l
        stack.setCustomSpacing(Spacing.xl, after: markHolder)
        stack.setCustomSpacing(Spacing.s, after: titleLabel)
        stack.setCustomSpacing(Spacing.xl, after: steps)
        stack.setCustomSpacing(Spacing.s, after: codeField)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let centerY = card.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        centerY.priority = .defaultLow
        let fillWidth = card.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -Spacing.xl * 2)
        fillWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            gradient.topAnchor.constraint(equalTo: view.topAnchor),
            gradient.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gradient.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),

            card.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            fillWidth,
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            centerY,
            card.topAnchor.constraint(greaterThanOrEqualTo: contentView.safeAreaLayoutGuide.topAnchor, constant: Spacing.xl),
            card.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Spacing.xl),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: Spacing.xxl),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Spacing.xl),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Spacing.xl),

            mark.heightAnchor.constraint(equalToConstant: 64),
            mark.widthAnchor.constraint(equalToConstant: 64),
            mark.topAnchor.constraint(equalTo: markHolder.topAnchor),
            mark.bottomAnchor.constraint(equalTo: markHolder.bottomAnchor),
            mark.centerXAnchor.constraint(equalTo: markHolder.centerXAnchor),
            codeField.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])

    }

    private func makeStepRow(number: Int, text: String) -> UIView {
        let badge = UILabel()
        badge.text = String(number)
        badge.textAlignment = .center
        badge.font = Typography.rounded(.subheadline, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = Palette.accent
        badge.layer.cornerRadius = 13
        badge.layer.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 26),
            badge.heightAnchor.constraint(equalToConstant: 26)
        ])

        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = Typography.font(.subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.textSecondary

        let row = UIStackView(arrangedSubviews: [badge, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = Spacing.m
        return row
    }

    private func configureContent() {
        titleLabel.text = L10n.tr("activation.title")
        titleLabel.font = Typography.rounded(.title1, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        subtitleLabel.text = L10n.tr("activation.subtitle")
        subtitleLabel.font = Typography.font(.body)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = Palette.textSecondary
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        codeField.delegate = self
        codeField.placeholder = L10n.tr("activation.code.placeholder")
        codeField.accessibilityLabel = L10n.tr("activation.code.label")
        codeField.font = UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .monospacedSystemFont(ofSize: 22, weight: .semibold)
        )
        codeField.adjustsFontForContentSizeCategory = true
        codeField.textAlignment = .center
        codeField.autocapitalizationType = .allCharacters
        codeField.autocorrectionType = .no
        codeField.spellCheckingType = .no
        codeField.smartDashesType = .no
        codeField.keyboardType = .asciiCapable
        codeField.returnKeyType = .go
        codeField.textContentType = .oneTimeCode
        codeField.backgroundColor = Palette.card
        codeField.layer.cornerRadius = 14
        codeField.layer.cornerCurve = .continuous
        codeField.layer.borderWidth = 1
        codeField.layer.borderColor = UIColor.clear.cgColor
        codeField.addTarget(self, action: #selector(handleReturn), for: .editingDidEndOnExit)

        errorLabel.font = Typography.font(.footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = Palette.destructive
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        submitButton.addTarget(self, action: #selector(submit), for: .touchUpInside)

        hintLabel.text = L10n.tr("activation.hint")
        hintLabel.font = Typography.font(.footnote)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textColor = Palette.textTertiary
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
    }

    // MARK: - Ввод

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let current = textField.text ?? ""
        guard let swiftRange = Range(range, in: current) else { return false }
        let updated = current.replacingCharacters(in: swiftRange, with: string)
        textField.text = ActivationCode.format(updated)
        hideError()
        updateSubmitState()
        return false
    }

    @objc private func handleReturn() {
        submit()
    }

    private func updateSubmitState() {
        submitButton.isEnabled = ActivationCode.isComplete(codeField.text ?? "") && !isSubmitting
    }

    // MARK: - Отправка

    @objc private func submit() {
        let code = codeField.text ?? ""
        guard ActivationCode.isComplete(code), !isSubmitting else { return }
        isSubmitting = true
        submitButton.isLoading = true
        hideError()
        codeField.resignFirstResponder()

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let account = try await self.auth.activate(code: code)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.isSubmitting = false
                self.submitButton.isLoading = false
                self.onActivated(account)
            } catch {
                self.isSubmitting = false
                self.submitButton.isLoading = false
                self.updateSubmitState()
                self.showError(APIError.wrap(error))
            }
        }
    }

    private func showError(_ error: APIError) {
        let message: String
        switch error {
        case .notFound:
            message = L10n.tr("activation.error.invalid_code")
        case .conflict(let code) where code == "code_used":
            message = L10n.tr("activation.error.code_used")
        case .accountInactive:
            message = L10n.tr("activation.error.account_inactive")
        case .rateLimited:
            message = L10n.tr("error.rate_limited.message")
        case .offline, .timedOut, .transport:
            message = L10n.tr("error.offline.message")
        default:
            message = L10n.tr("activation.error.generic")
        }
        errorLabel.text = message
        errorLabel.isHidden = false
        codeField.layer.borderColor = Palette.destructive.cgColor
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        UIAccessibility.post(notification: .announcement, argument: message)

        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [-10, 10, -7, 7, -4, 4, 0]
        shake.duration = 0.4
        codeField.layer.add(shake, forKey: "shake")
    }

    private func hideError() {
        guard !errorLabel.isHidden else { return }
        errorLabel.isHidden = true
        codeField.layer.borderColor = UIColor.clear.cgColor
    }
}
