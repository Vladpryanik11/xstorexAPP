import UIKit

/// Палитра iStore (SPEC §3).
enum Palette {
    // MARK: Бренд

    /// Бренд-градиент: сверху справа → снизу слева.
    static let brandGradient: [UIColor] = [
        UIColor(red: 0x00 / 255, green: 0x41 / 255, blue: 0xDC / 255, alpha: 1), // #0041DC
        UIColor(red: 0x36 / 255, green: 0x72 / 255, blue: 0xE0 / 255, alpha: 1), // #3672E0
        UIColor(red: 0x6A / 255, green: 0xA2 / 255, blue: 0xE3 / 255, alpha: 1), // #6AA2E3
        UIColor(red: 0x92 / 255, green: 0xBD / 255, blue: 0xEF / 255, alpha: 1)  // #92BDEF
    ]

    /// Тёмный вариант бренда.
    static let brandDarkGradient: [UIColor] = [
        UIColor(red: 0x18 / 255, green: 0x42 / 255, blue: 0x9D / 255, alpha: 1), // #18429D
        UIColor(red: 0x0D / 255, green: 0x23 / 255, blue: 0x53 / 255, alpha: 1)  // #0D2353
    ]

    static let brandBlue = UIColor(red: 0x00 / 255, green: 0x41 / 255, blue: 0xDC / 255, alpha: 1)
    static let brandBlueDark = UIColor(red: 0x36 / 255, green: 0x72 / 255, blue: 0xE0 / 255, alpha: 1)

    /// Акцент: `#0041DC`, в тёмной теме `#3672E0`.
    static let accent = UIColor.dynamic(light: brandBlue, dark: brandBlueDark)

    // MARK: Поверхности

    static let background = UIColor.systemBackground
    static let groupedBackground = UIColor.systemGroupedBackground
    static let card = UIColor.secondarySystemBackground
    static let elevatedCard = UIColor.dynamic(
        light: .white,
        dark: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let separator = UIColor.separator
    static let skeleton = UIColor.dynamic(
        light: UIColor(white: 0.92, alpha: 1),
        dark: UIColor(white: 0.18, alpha: 1)
    )

    // MARK: Текст

    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel
    static let textTertiary = UIColor.tertiaryLabel

    // MARK: Кнопка установки

    /// Фон мини-кнопки «Загрузить» на полках, как в App Store.
    static let installFill = UIColor.dynamic(
        light: UIColor(white: 0.94, alpha: 1),
        dark: UIColor(white: 0.22, alpha: 1)
    )

    static let destructive = UIColor.systemRed
    static let success = UIColor.systemGreen

    // MARK: Цвета приложения

    /// Акцент карточки приложения из `tint_light` / `tint_dark`.
    static func tint(light: String?, dark: String?) -> UIColor {
        let lightColor = light.flatMap { UIColor(hex: $0) } ?? brandBlue
        let darkColor = dark.flatMap { UIColor(hex: $0) } ?? lightColor.blended(with: .white, fraction: 0.25)
        return .dynamic(light: lightColor, dark: darkColor)
    }

    /// Фон hero-шапки из `bg_color`: в тёмной теме он приглушается.
    static func heroBackground(hex: String?, tintLight: String?) -> UIColor {
        let base = hex.flatMap { UIColor(hex: $0) }
            ?? tintLight.flatMap { UIColor(hex: $0) }?.blended(with: .white, fraction: 0.88)
            ?? UIColor(red: 0.92, green: 0.95, blue: 1, alpha: 1)
        let dark = base.blended(with: UIColor(white: 0.08, alpha: 1), fraction: 0.82)
        return .dynamic(light: base, dark: dark)
    }
}

/// Отступы.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 32
    /// Максимальная ширина контента на iPad.
    static let maxContentWidth: CGFloat = 720
}

/// Шрифты с поддержкой Dynamic Type.
enum Typography {
    /// Базовый размер считается для категории `.large`, масштабирует `UIFontMetrics`.
    static let defaultTraits = UITraitCollection(preferredContentSizeCategory: .large)

    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: Typography.defaultTraits)
        let font = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: Typography.defaultTraits)
        let system = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        let font: UIFont
        if let descriptor = system.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: base.pointSize)
        } else {
            font = system
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
}
