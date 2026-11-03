import UIKit

/// Обновление самого iStore. Необязательное — шит с «Обновить» и «Не сейчас»;
/// обязательное — неснимаемый экран в отдельном окне поверх всего.
final class ClientUpdateViewController: UIViewController {
    private let version: ClientVersion
    private let mandatory: Bool
    private let onUpdate: (URL) -> Void
    private let onLater: () -> Void

    private let gradient = BrandGradientView()
    private let mark = BrandMarkView()
    private let titleLabel = UILabel()
    private let versionLabel = UILabel()
    private let notesLabel = UILabel()
    private let hintLabel = UILabel()
    private let updateButton = PrimaryButton(title: L10n.tr("update.action"))
    private let laterButton = UIButton(type: .system)

    init(version: ClientVersion, mandatory: Bool, onUpdate: @escaping (URL) -> Void, onLater: @escaping () -> Void) {
        self.version = version
        self.mandatory = mandatory
        self.onUpdate = onUpdate
        self.onLater = onLater
        super.init(nibName: nil, bundle: nil)
        isModalInPresentation = mandatory
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = mandatory ? Palette.brandBlue : Palette.background
        if mandatory {
            gradient.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(gradient)
            NSLayoutConstraint.activate([
                gradient.topAnchor.constraint(equalTo: view.topAnchor),
                gradient.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                gradient.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                gradient.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }

        let textColor: UIColor = mandatory ? .white : Palette.textPrimary
        let secondaryColor: UIColor = mandatory ? UIColor.white.withAlphaComponent(0.8) : Palette.textSecondary

        titleLabel.text = L10n.tr(mandatory ? "update.mandatory.title" : "update.title")
        titleLabel.font = Typography.rounded(.title1, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = textColor
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header

        versionLabel.text = L10n.tr("update.version_format", version.latestVersion)
        versionLabel.font = Typography.font(.subheadline, weight: .semibold)
        versionLabel.adjustsFontForContentSizeCategory = true
        versionLabel.textColor = secondaryColor
        versionLabel.textAlignment = .center

        notesLabel.text = version.releaseNotes
        notesLabel.font = Typography.font(.body)
        notesLabel.adjustsFontForContentSizeCategory = true
        notesLabel.textColor = textColor
        notesLabel.numberOfLines = 0
        notesLabel.textAlignment = .center
        notesLabel.isHidden = (version.releaseNotes ?? "").isEmpty

        hintLabel.text = L10n.tr(mandatory ? "update.mandatory.message" : "update.hint")
        hintLabel.font = Typography.font(.footnote)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textColor = secondaryColor
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center

        updateButton.addTarget(self, action: #selector(handleUpdate), for: .touchUpInside)
        updateButton.isEnabled = version.updateUrl != nil

        laterButton.setTitle(L10n.tr("update.later"), for: .normal)
        laterButton.titleLabel?.font = Typography.font(.body, weight: .semibold)
        laterButton.titleLabel?.adjustsFontForContentSizeCategory = true
        laterButton.addTarget(self, action: #selector(handleLater), for: .touchUpInside)
        laterButton.isHidden = mandatory

        let markHolder = UIView()
        mark.translatesAutoresizingMaskIntoConstraints = false
        markHolder.addSubview(mark)

        let stack = UIStackView(arrangedSubviews: [
            markHolder, titleLabel, versionLabel, notesLabel, hintLabel, updateButton, laterButton
        ])
        stack.axis = .vertical
        stack.spacing = Spacing.m
        stack.setCustomSpacing(Spacing.l, after: markHolder)
        stack.setCustomSpacing(Spacing.xl, after: hintLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        let preferredWidth = stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -Spacing.xl * 2)
        preferredWidth.priority = .defaultHigh
        let centerY = stack.centerYAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerYAnchor)
        centerY.priority = .defaultLow

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(greaterThanOrEqualTo: scrollView.contentLayoutGuide.topAnchor, constant: Spacing.xxl),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Spacing.xl),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            preferredWidth,
            centerY,

            mark.widthAnchor.constraint(equalToConstant: 72),
            mark.heightAnchor.constraint(equalToConstant: 72),
            mark.topAnchor.constraint(equalTo: markHolder.topAnchor),
            mark.bottomAnchor.constraint(equalTo: markHolder.bottomAnchor),
            mark.centerXAnchor.constraint(equalTo: markHolder.centerXAnchor)
        ])
    }

    @objc private func handleUpdate() {
        guard let url = version.updateUrl else { return }
        onUpdate(url)
        if !mandatory {
            dismiss(animated: true)
        }
    }

    @objc private func handleLater() {
        onLater()
        dismiss(animated: true)
    }
}
