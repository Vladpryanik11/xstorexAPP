import UIKit

/// Section provider'ы витрины: по одному на стиль комнаты.
@MainActor
enum StorefrontLayout {
    private static let sideInset: CGFloat = 20

    private static func isWide(_ environment: NSCollectionLayoutEnvironment) -> Bool {
        environment.container.effectiveContentSize.width >= 700
    }

    /// Высота с учётом Dynamic Type, но с ограничением сверху.
    private static func scaled(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        min(UIFontMetrics.default.scaledValue(for: value), limit)
    }

    static func header() -> NSCollectionLayoutBoundarySupplementaryItem {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(52))
        return NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: size,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    /// hero_carousel: широкие карточки, листаются по одной с центрированием.
    static func heroSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let wide = isWide(environment)
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        ))
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(wide ? 0.62 : 0.9),
            heightDimension: .absolute(scaled(wide ? 340 : 300, limit: 420))
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPagingCentered
        section.interGroupSpacing = Spacing.m
        section.contentInsets = NSDirectionalEdgeInsets(top: Spacing.s, leading: 0, bottom: Spacing.l, trailing: 0)
        section.supplementariesFollowContentInsets = false
        return section
    }

    /// shelf_one: колонки по три строки, горизонтальный пейджинг.
    static func shelfOneSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let wide = isWide(environment)
        let rowHeight = scaled(80, limit: 130)
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1.0 / 3.0)
        ))
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(wide ? 0.46 : 0.88),
            heightDimension: .absolute(rowHeight * 3)
        )
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPaging
        section.interGroupSpacing = Spacing.l
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sideInset, bottom: Spacing.l, trailing: sideInset)
        section.supplementariesFollowContentInsets = false
        return section
    }

    /// shelf_two: крупные карточки.
    static func shelfTwoSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let wide = isWide(environment)
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        ))
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(wide ? 0.38 : 0.72),
            heightDimension: .absolute(scaled(250, limit: 360))
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .groupPaging
        section.interGroupSpacing = Spacing.m
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sideInset, bottom: Spacing.l, trailing: sideInset)
        section.supplementariesFollowContentInsets = false
        return section
    }

    /// chips: горизонтальные капсулы категорий.
    static func chipsSection() -> NSCollectionLayoutSection {
        let height = scaled(38, limit: 60)
        let size = NSCollectionLayoutSize(widthDimension: .estimated(120), heightDimension: .absolute(height))
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = Spacing.s
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sideInset, bottom: Spacing.l, trailing: sideInset)
        section.supplementariesFollowContentInsets = false
        return section
    }

    /// Скелетон на время первой загрузки.
    static func skeletonSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        ))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(84)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: Spacing.l, leading: sideInset, bottom: 0, trailing: sideInset)
        return section
    }

    /// Вертикальный список строк (экраны «Показать все», поиск).
    static func listSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let wide = isWide(environment)
        let columns = wide ? 2 : 1
        let rowHeight = scaled(84, limit: 140)
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: .fractionalHeight(1)
        ))
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: wide ? Spacing.s : 0, bottom: 0, trailing: wide ? Spacing.s : 0)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(rowHeight)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: Spacing.s, leading: sideInset, bottom: Spacing.l, trailing: sideInset)
        section.supplementariesFollowContentInsets = false
        return section
    }
}
