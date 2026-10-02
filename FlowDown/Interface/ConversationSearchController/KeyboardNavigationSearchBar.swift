//
//  KeyboardNavigationSearchBar.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/9/25.
//

import UIKit

class KeyboardNavigationSearchBar: UISearchBar {
    weak var keyboardNavigationDelegate: KeyboardNavigationDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupKeyboardHandling()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeyboardHandling()
    }

    private func setupKeyboardHandling() {}

    /// The arrows have to win over the search field, which is the first
    /// responder and would otherwise spend them on moving the caret before
    /// they ever reach the bar. Return is left to the field, where
    /// `searchBarSearchButtonClicked` already opens the highlighted result.
    override var keyCommands: [UIKeyCommand]? {
        let upArrow = UIKeyCommand(
            input: UIKeyCommand.inputUpArrow,
            modifierFlags: [],
            action: #selector(handleKeyboardNavigationUpArrow),
        )
        upArrow.wantsPriorityOverSystemBehavior = true
        let downArrow = UIKeyCommand(
            input: UIKeyCommand.inputDownArrow,
            modifierFlags: [],
            action: #selector(handleKeyboardNavigationDownArrow),
        )
        downArrow.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [upArrow, downArrow]
    }

    @objc private func handleKeyboardNavigationUpArrow() {
        keyboardNavigationDelegate?.didPressUpArrow()
    }

    @objc private func handleKeyboardNavigationDownArrow() {
        keyboardNavigationDelegate?.didPressDownArrow()
    }
}
