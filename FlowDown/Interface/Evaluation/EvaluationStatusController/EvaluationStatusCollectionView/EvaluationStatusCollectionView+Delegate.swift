//
//  EvaluationStatusCollectionView+Delegate.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import UIKit

extension EvaluationStatusCollectionView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        guard let caseItem = caseItem(for: item) else { return }
        onSelectCase?(caseItem)
    }

    func collectionView(
        _: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        guard let caseItem = caseItem(for: item) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return EvaluationMenuFactory.makeMenu(
                session: session,
                caseItem: caseItem,
                onUpdate: { [weak self] in
                    self?.applySessionUpdate()
                },
            )
        }
    }
}
