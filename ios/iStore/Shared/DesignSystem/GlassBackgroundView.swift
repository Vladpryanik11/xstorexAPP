import UIKit

/// Стеклянная подложка: на iOS 26+ системный `UIGlassEffect`, ниже — `systemUltraThinMaterial`.
final class GlassBackgroundView: UIView {
    let effectView: UIVisualEffectView

    /// Сюда кладутся подвиды поверх стекла.
    var contentView: UIView { effectView.contentView }

    var cornerRadius: CGFloat = 0 {
        didSet {
            effectView.layer.cornerRadius = cornerRadius
            layer.cornerRadius = cornerRadius
        }
    }

    init(cornerRadius: CGFloat = 0) {
        effectView = UIVisualEffectView(effect: GlassBackgroundView.makeEffect())
        super.init(frame: .zero)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.clipsToBounds = true
        effectView.layer.cornerCurve = .continuous
        layer.cornerCurve = .continuous
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        self.cornerRadius = cornerRadius
        effectView.layer.cornerRadius = cornerRadius
        layer.cornerRadius = cornerRadius
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func makeEffect() -> UIVisualEffect {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return UIGlassEffect(style: .regular)
        }
        #endif
        return UIBlurEffect(style: .systemUltraThinMaterial)
    }
}
