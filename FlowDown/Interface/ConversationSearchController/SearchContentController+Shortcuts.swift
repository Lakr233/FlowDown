//
//  SearchContentController+Shortcuts.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/9/25.
//

extension SearchContentController: KeyboardNavigationDelegate {
    func didPressUpArrow() {
        guard !searchResults.isEmpty else { return }

        if var currentIndex = focusedIndexPath {
            currentIndex.row -= 1
            currentIndex.row = max(currentIndex.row, 0)
            updateHighlightedIndex(currentIndex)
        } else {
            updateHighlightedIndex(.init(row: searchResults.count - 1, section: 0))
        }
    }

    func didPressDownArrow() {
        guard !searchResults.isEmpty else { return }

        if var currentIndex = focusedIndexPath {
            currentIndex.row += 1
            currentIndex.row = min(currentIndex.row, searchResults.count - 1)
            updateHighlightedIndex(currentIndex)
        } else {
            updateHighlightedIndex(.init(row: 0, section: 0))
        }
    }
}
