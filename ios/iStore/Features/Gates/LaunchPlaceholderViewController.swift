import UIKit

/// Экран-заглушка под шлюзами на холодном старте: бренд-градиент и знак iStore.
final class LaunchPlaceholderViewController: UIViewController {
    private let gradient = BrandGradientView()
    private let mark = BrandMarkView()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.brandBlue
        gradient.translatesAutoresizingMaskIntoConstraints = false
        mark.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = .white
        spinner.startAnimating()
        spinner.accessibilityLabel = L10n.tr("common.loading")

        view.addSubview(gradient)
        view.addSubview(mark)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            gradient.topAnchor.constraint(equalTo: view.topAnchor),
            gradient.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gradient.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mark.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            mark.widthAnchor.constraint(equalToConstant: 96),
            mark.heightAnchor.constraint(equalToConstant: 96),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: mark.bottomAnchor, constant: Spacing.xxl)
        ])
        mark.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        mark.layer.borderWidth = 1
    }
}
