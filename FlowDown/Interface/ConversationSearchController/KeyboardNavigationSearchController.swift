//
//  KeyboardNavigationSearchController.swift
//  FlowDown
//
//  Created by 秋星桥 on 10/2/26.
//

import UIKit

/// A search controller whose search bar moves through results with the arrow
/// keys. `UISearchController` creates its own bar, so the only way to give it
/// `KeyboardNavigationSearchBar` is to hand that bar out in its place.
final class KeyboardNavigationSearchController: UISearchController {
    private lazy var navigationSearchBar = KeyboardNavigationSearchBar()

    override var searchBar: UISearchBar {
        navigationSearchBar
    }
}
