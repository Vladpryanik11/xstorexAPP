import UIKit

/// Кнопка установки: капсула «Загрузить / Открыть / Обновить», во время установки — круг
/// с кольцом прогресса (`CAShapeLayer`) или неопределённым спиннером.
final class InstallButton: UIControl {
    enum Size {
        case regular
        case mini

        var height: CGFloat { self == .regular ? 32 : 28 }
        var minWidth: CGFloat { self == .regular ? 88 : 76 }
        var horizontalPadding: CGFloat { self == .regular ? 18 : 14 }
        var ringWidth: CGFloat { self == .regular ? 3 : 2.5 }
    }

    enum Mode {
        case get
        case open
        case update
    }

    private let size: Size
    /// `true` — заливка акцентом и белый текст (hero карточки), `false` — серая капсула с акцентным текстом.
    private let prominent: Bool

    private let capsule = UIView()
    private let titleLabel = UILabel()
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let spinnerLayer = CAShapeLayer()
    private let stopSquare = UIView()

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    private(set) var installState: InstallState = .idle
    var mode: Mode = .get {
        didSet { refresh(animated: false) }
    }

    /// Вызывается по тапу (в дополнение к `.touchUpInside`).
    var onTap: (() -> Void)?

    /// Цвет акцента; по умолчанию — акцент бренда.
    var accentColor: UIColor = Palette.accent {
        didSet { refresh(animated: false) }
    }

    init(size: Size = .regular, prominent: Bool = false) {
        self.size = size
        self.prominent = prominent
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        isAccessibilityElement = true
        accessibilityTraits = .button

        capsule.isUserInteractionEnabled = false
        capsule.layer.cornerCurve = .continuous
        addSubview(capsule)

        titleLabel.isUserInteractionEnabled = false
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: size == .regular ? 15 : 14, weight: .bold),
            maximumPointSize: size == .regular ? 20 : 18
        )
        addSubview(titleLabel)

        for shape in [trackLayer, progressLayer, spinnerLayer] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineWidth = size.ringWidth
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        progressLayer.strokeEnd = 0

        stopSquare.isUserInteractionEnabled = false
        stopSquare.layer.cornerRadius = 2
        addSubview(stopSquare)

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        refresh(animated: false)
    }

    // MARK: - Состояние

    func apply(_ state: InstallState, animated: Bool = true) {
        let previous = installState
        installState = state
        if previous != state {
            switch state {
            case .handingOff:
                notification.notificationOccurred(.success)
            case .failed:
                if previous.isActive {
                    notification.notificationOccurred(.error)
                }
            default:
                break
            }
        }
        refresh(animated: animated)
    }

    private var showsCircle: Bool {
        installState.isActive
    }

    private var title: String {
        switch installState {
        case .failed:
            return L10n.tr("install.button.retry")
        default:
            switch mode {
            case .get: return L10n.tr("install.button.get")
            case .open: return L10n.tr("install.button.open")
            case .update: return L10n.tr("install.button.update")
            }
        }
    }

    private func refresh(animated: Bool) {
        let accent = accentColor.resolvedColor(with: traitCollection)
        titleLabel.text = title
        titleLabel.textColor = prominent ? .white : accent
        capsule.backgroundColor = prominent ? accent : Palette.installFill.resolvedColor(with: traitCollection)

        let circle = showsCircle
        capsule.alpha = circle ? 0 : 1
        titleLabel.alpha = circle ? 0 : 1

        trackLayer.strokeColor = Palette.installFill.resolvedColor(with: traitCollection).cgColor
        progressLayer.strokeColor = accent.cgColor
        spinnerLayer.strokeColor = accent.cgColor
        stopSquare.backgroundColor = accent
        trackLayer.isHidden = !circle
        progressLayer.isHidden = !circle

        let progress = installState.progress
        let indeterminate = circle && progress == nil || installState == .installing
        spinnerLayer.isHidden = !indeterminate
        stopSquare.isHidden = !(circle && installState == .ready)

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        progressLayer.strokeEnd = CGFloat(indeterminate ? 0 : (progress ?? 0))
        CATransaction.commit()

        if indeterminate {
            startSpinning()
        } else {
            spinnerLayer.removeAnimation(forKey: "spin")
        }

        updateAccessibility()
        invalidateIntrinsicContentSize()
        if animated, window != nil {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                self.superview?.layoutIfNeeded()
                self.layoutIfNeeded()
            }
        } else {
            setNeedsLayout()
        }
    }

    private func updateAccessibility() {
        switch installState {
        case .idle, .failed:
            accessibilityLabel = title
            accessibilityValue = nil
        case .preparing:
            accessibilityLabel = L10n.tr("install.status.preparing")
            accessibilityValue = nil
        case .ready:
            accessibilityLabel = L10n.tr("install.status.ready")
            accessibilityValue = percentString(0.5)
        case .handingOff:
            accessibilityLabel = L10n.tr("install.status.handing_off")
            accessibilityValue = percentString(0.8)
        case .installing:
            accessibilityLabel = L10n.tr("install.status.installing")
            accessibilityValue = nil
        }
    }

    private func percentString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    private func startSpinning() {
        guard spinnerLayer.animation(forKey: "spin") == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = CGFloat.pi * 2
        animation.duration = 0.9
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        spinnerLayer.add(animation, forKey: "spin")
    }

    // MARK: - Раскладка

    override var intrinsicContentSize: CGSize {
        if showsCircle {
            return CGSize(width: size.height, height: size.height)
        }
        let textWidth = titleLabel.intrinsicContentSize.width
        let width = max(size.minWidth, ceil(textWidth) + size.horizontalPadding * 2)
        return CGSize(width: width, height: max(size.height, titleLabel.intrinsicContentSize.height + 8))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        capsule.frame = bounds
        capsule.layer.cornerRadius = bounds.height / 2
        titleLabel.frame = bounds.insetBy(dx: 6, dy: 0)

        let side = min(bounds.width, bounds.height)
        let ringRect = CGRect(
            x: bounds.maxX - side,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        ).insetBy(dx: size.ringWidth / 2 + 1, dy: size.ringWidth / 2 + 1)

        let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
        let radius = ringRect.width / 2
        let fullCircle = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -CGFloat.pi / 2,
            endAngle: CGFloat.pi * 1.5,
            clockwise: true
        )
        trackLayer.frame = bounds
        progressLayer.frame = bounds
        trackLayer.path = fullCircle.cgPath
        progressLayer.path = fullCircle.cgPath

        // Спиннер вращается вокруг своего центра, поэтому слой совпадает с кольцом.
        spinnerLayer.frame = ringRect
        let local = CGPoint(x: ringRect.width / 2, y: ringRect.height / 2)
        spinnerLayer.path = UIBezierPath(
            arcCenter: local,
            radius: radius,
            startAngle: 0,
            endAngle: CGFloat.pi * 1.4,
            clockwise: true
        ).cgPath

        let square = side * 0.3
        stopSquare.frame = CGRect(x: center.x - square / 2, y: center.y - square / 2, width: square, height: square)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            refresh(animated: false)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refresh(animated: false)
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.55 : 1
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Минимальная зона касания 44 pt.
        let dx = min(0, (bounds.width - 44) / 2)
        let dy = min(0, (bounds.height - 44) / 2)
        return bounds.insetBy(dx: dx, dy: dy).contains(point)
    }

    @objc private func handleTap() {
        impact.impactOccurred()
        onTap?()
    }
}
