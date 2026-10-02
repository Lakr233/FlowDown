//
//  EvaluationStatusCollectionView+Layout.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import SnapKit
import UIKit

extension EvaluationStatusCollectionView {
    func createLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let minItemWidth: CGFloat = 150
            let maxItemWidth: CGFloat = 250

            let interItemSpacing: CGFloat = 10
            let sectionInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

            let availableWidth = environment.container.effectiveContentSize.width
                - sectionInsets.leading
                - sectionInsets.trailing

            var columns = max(
                1,
                Int(((availableWidth + interItemSpacing) / (minItemWidth + interItemSpacing)).rounded(.down))
            )
            if columns < 1 { columns = 1 }

            func itemWidth(for columns: Int) -> CGFloat {
                guard columns > 0 else { return availableWidth }
                let totalSpacing = interItemSpacing * CGFloat(max(0, columns - 1))
                return (availableWidth - totalSpacing) / CGFloat(columns)
            }

            while columns < 20, itemWidth(for: columns) > maxItemWidth {
                columns += 1
            }
            while columns > 1, itemWidth(for: columns) < minItemWidth {
                columns -= 1
            }

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .estimated(80),
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(80),
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(interItemSpacing)

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = sectionInsets
            section.interGroupSpacing = 16

            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(30),
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top,
            )
            header.pinToVisibleBounds = true
            section.boundarySupplementaryItems = [header]
            return section
        }
    }
}
