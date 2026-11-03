import UIKit

/// Диагональный градиент (сверху справа → снизу слева) на `CAGradientLayer`.
final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer {
        // `layerClass` гарантирует тип слоя.
        layer as! CAGradientLayer
    }

    var colors: [UIColor] = [] {
        didSet { applyColors() }
    }

    init(colors: [UIColor] = [], diagonal: Bool = true) {
        self.colors = colors
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        if diagonal {
            gradientLayer.startPoint = CGPoint(x: 1, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0, y: 1)
        } else {
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        }
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPoints(start: CGPoint, end: CGPoint) {
        gradientLayer.startPoint = start
        gradientLayer.endPoint = end
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
    }

    private func applyColors() {
        let traits = traitCollection
        gradientLayer.colors = colors.map { $0.resolvedColor(with: traits).cgColor }
    }
}

/// Бренд-градиент iStore. `dark = true` — тёмный вариант `#18429D → #0D2353`.
final class BrandGradientView: UIView {
    private let gradient: GradientView

    init(dark: Bool = false) {
        gradient = GradientView(colors: dark ? Palette.brandDarkGradient : Palette.brandGradient)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        gradient.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gradient)
        NSLayoutConstraint.activate([
            gradient.topAnchor.constraint(equalTo: topAnchor),
            gradient.bottomAnchor.constraint(equalTo: bottomAnchor),
            gradient.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Знак iStore: монограмма «i» на бренд-градиенте, как иконка приложения.
final class BrandMarkView: UIView {
    private let gradient = GradientView(colors: Palette.brandGradient)
    private let stem = UIView()
    private let dot = UIView()

    init() {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = L10n.tr("brand.name")
        accessibilityTraits = .image
        clipsToBounds = true
        layer.cornerCurve = .continuous
        addSubview(gradient)
        stem.backgroundColor = .white
        dot.backgroundColor = .white
        addSubview(stem)
        addSubview(dot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width, bounds.height)
        layer.cornerRadius = side * 0.2237
        gradient.frame = bounds
        let stemWidth = side * 0.17
        let stemHeight = side * 0.40
        stem.frame = CGRect(
            x: bounds.midX - stemWidth / 2,
            y: bounds.midY - side * 0.10,
            width: stemWidth,
            height: stemHeight
        )
        stem.layer.cornerRadius = stemWidth / 2
        let dotSide = side * 0.19
        dot.frame = CGRect(
            x: bounds.midX - dotSide / 2,
            y: bounds.midY - side * 0.33,
            width: dotSide,
            height: dotSide
        )
        dot.layer.cornerRadius = dotSide / 2
    }
}
