import UIKit

/// Иконка приложения: скругление continuous 22.37 % стороны и тонкая обводка, как на домашнем экране.
final class AppIconView: UIView {
    private let imageView = RemoteImageView(frame: .zero)
    private let fallbackSymbol = UIImageView()

    init() {
        super.init(frame: .zero)
        isAccessibilityElement = false
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        fallbackSymbol.translatesAutoresizingMaskIntoConstraints = false
        fallbackSymbol.image = UIImage(systemName: "app.fill")
        fallbackSymbol.tintColor = Palette.textTertiary
        fallbackSymbol.contentMode = .scaleAspectFit
        fallbackSymbol.isHidden = true
        addSubview(fallbackSymbol)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallbackSymbol.centerXAnchor.constraint(equalTo: centerXAnchor),
            fallbackSymbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            fallbackSymbol.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            fallbackSymbol.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5)
        ])
        updateBorder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) * 0.2237
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorder()
    }

    func setIcon(url: URL?, pipeline: ImagePipeline = .shared) {
        fallbackSymbol.isHidden = url != nil
        imageView.setImage(url: url, pipeline: pipeline)
    }

    func reset() {
        imageView.reset()
        fallbackSymbol.isHidden = true
    }

    private func updateBorder() {
        layer.borderColor = Palette.separator.resolvedColor(with: traitCollection).withAlphaComponent(0.25).cgColor
    }
}
