//
//  FadeBarNavigationController.swift
//  FlowDown
//
//  A navigation controller whose bar has no background and no divider: what
//  scrolls under it passes through the soft progressive edge instead
//  (`ProgressiveBlurView`), and its buttons carry their own surface —
//  the system's glass on iOS 26 and later, `FloatingButtonSurfaceView`
//  circles and capsules before. On the Mac it is a plain navigation
//  controller.
//

import SnapKit
import UIKit

class FadeBarNavigationController: UINavigationController {
    #if !targetEnvironment(macCatalyst)
        /// The soft edge under the bar: from the top of the view to 16 pt
        /// below the bar's buttons (or its search field), so a page's first
        /// line rests below it.
        private let topEdgeBlur = ProgressiveBlurView()
        /// Bar items this controller made, so they are not wrapped twice.
        private var floatingItems: Set<ObjectIdentifier> = []
        /// What each navigation item's bar items were when last restyled.
        private var styledItems: [ObjectIdentifier: [ObjectIdentifier]] = [:]
        /// The replaced items, kept alive and followed, by the floating
        /// item that stands in for each.
        private var replacedItems: [ObjectIdentifier: (item: UIBarButtonItem, observations: [NSKeyValueObservation])] = [:]
    #endif

    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        #if !targetEnvironment(macCatalyst)
            configureFadeBar()
        #endif
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        #if !targetEnvironment(macCatalyst)
            configureFadeBar()
        #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    #if !targetEnvironment(macCatalyst)
        private func configureFadeBar() {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
            appearance.titleTextAttributes = [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor.label,
            ]
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
            navigationBar.compactScrollEdgeAppearance = appearance
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.insertSubview(topEdgeBlur, belowSubview: navigationBar)
            // A custom back button turns the edge swipe off unless the
            // recogniser is told when it may begin.
            interactivePopGestureRecognizer?.delegate = self
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            // Pushes can reorder the controller's views; keep the edge right
            // under the bar, over the pages.
            if let edgeIndex = view.subviews.firstIndex(of: topEdgeBlur),
               let barIndex = view.subviews.firstIndex(of: navigationBar),
               edgeIndex + 1 != barIndex
            {
                view.insertSubview(topEdgeBlur, belowSubview: navigationBar)
            }
            // The bar's buttons sit in its standard row, at its top; whatever
            // the bar stacks below that row (a search field) is chrome too.
            // The bar itself runs past its lowest control (10 pt on iOS 26),
            // so the edge is measured from the control, not the bar's frame.
            let bar = navigationBar.frame
            var buttonBottom = view.safeAreaInsets.top
            if !navigationBar.isHidden {
                buttonBottom = min(bar.maxY, bar.minY + FloatingChrome.buttonSize)
                if let field = topViewController?.navigationItem.searchController?.searchBar.searchTextField,
                   field.window != nil, !field.isHidden, field.isDescendant(of: navigationBar)
                {
                    let fieldBottom = field.convert(field.bounds, to: view).maxY
                    if fieldBottom > buttonBottom { buttonBottom = min(bar.maxY, fieldBottom) }
                }
            }
            // On iPhone Duo the bar can stand vertically along a side edge;
            // nothing stands over the top of the page then. The bar's frame
            // does not always say so, the trait does (read here, in layout,
            // so a change of edge lays the controller out again).
            var isVerticalBar = bar.height > bar.width
            // `verticalBarEdge` exists only in the iOS 27.1 SDK and later, so
            // `#available` alone does not compile with older Xcode (CI runs
            // Xcode 26). Swift 6.4.2 is Xcode 27.2's compiler; older
            // toolchains keep the frame check alone.
            #if !targetEnvironment(macCatalyst) && compiler(>=6.4.2)
                if #available(iOS 27.1, *), traitCollection.verticalBarEdge != .unspecified {
                    isVerticalBar = true
                }
            #endif
            topEdgeBlur.isHidden = navigationBar.isHidden || isVerticalBar
            topEdgeBlur.layoutAsBarEdge(CGRect(
                x: 0,
                y: 0,
                width: view.bounds.width,
                height: FloatingChrome.pageEdgeHeight(controlBottom: buttonBottom),
            ))
            for controller in viewControllers {
                applyFloatingChrome(to: controller)
            }
        }

        override func pushViewController(_ viewController: UIViewController, animated: Bool) {
            applyFloatingChrome(to: viewController, isRoot: viewControllers.isEmpty)
            super.pushViewController(viewController, animated: animated)
        }

        override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
            for (index, controller) in viewControllers.enumerated() {
                applyFloatingChrome(to: controller, isRoot: index == 0)
            }
            super.setViewControllers(viewControllers, animated: animated)
        }

        private func applyFloatingChrome(to controller: UIViewController, isRoot: Bool? = nil) {
            if controller.isViewLoaded {
                hideSystemTopEdge(in: controller)
            }
            guard !FloatingChrome.usesSystemGlass else { return }
            let isRoot = isRoot ?? (viewControllers.first === controller)
            restyleItems(of: controller, isRoot: isRoot)
        }

        // MARK: System edge

        /// The page's own scroll edge under the bar, turned off on iOS 26
        /// and later so it does not stack with the soft edge.
        private func hideSystemTopEdge(in controller: UIViewController) {
            if let scrollView = controller.contentScrollView(for: .top) {
                FloatingChrome.hideSystemTopEdge(of: scrollView)
                return
            }
            var queue: [UIView] = [controller.view]
            var depth = 0
            while !queue.isEmpty, depth < 4 {
                var next: [UIView] = []
                for view in queue {
                    if let scrollView = view as? UIScrollView {
                        FloatingChrome.hideSystemTopEdge(of: scrollView)
                    } else {
                        next.append(contentsOf: view.subviews)
                    }
                }
                queue = next
                depth += 1
            }
        }

        // MARK: Buttons before iOS 26

        /// Before iOS 26 the bar's items become floating buttons: icons in
        /// 44 pt circles, titles in 44 pt capsules, and a circular back
        /// button with no title. System glass does this on iOS 26.
        private func restyleItems(of controller: UIViewController, isRoot: Bool) {
            let item = controller.navigationItem
            let left = item.leftBarButtonItems ?? []
            let right = item.rightBarButtonItems ?? []
            let key = ObjectIdentifier(item)
            if styledItems[key] == (left + right).map(ObjectIdentifier.init) {
                return
            }

            var newLeft = left.map(floatingItem(for:))
            let newRight = right.map(floatingItem(for:))

            // The system back button would come back plain: a floating one
            // stands in for it, wherever the system would have shown it.
            if !isRoot, !newLeft.contains(where: isBackItem) {
                let systemShowsBack = left.isEmpty
                    ? !item.hidesBackButton
                    : item.leftItemsSupplementBackButton && !item.hidesBackButton
                if systemShowsBack {
                    newLeft.insert(makeBackItem(), at: 0)
                    item.hidesBackButton = true
                }
            }

            if newLeft.map(ObjectIdentifier.init) != left.map(ObjectIdentifier.init) {
                item.leftBarButtonItems = newLeft
            }
            if newRight.map(ObjectIdentifier.init) != right.map(ObjectIdentifier.init) {
                item.rightBarButtonItems = newRight
            }
            styledItems[key] = (newLeft + newRight).map(ObjectIdentifier.init)
        }

        private static let backItemTag = 0x0FAD_EBAC

        private func isBackItem(_ item: UIBarButtonItem) -> Bool {
            item.tag == Self.backItemTag
        }

        private func makeBackItem() -> UIBarButtonItem {
            let button = FloatingIconButton(systemName: "chevron.left")
            button.accessibilityLabel = String(localized: "Back")
            button.addAction(UIAction { [weak self] _ in
                self?.popViewController(animated: true)
            }, for: .touchUpInside)
            let item = barItem(wrapping: button)
            item.tag = Self.backItemTag
            item.accessibilityLabel = button.accessibilityLabel
            return item
        }

        /// The item as a floating button that does what it did, or the item
        /// itself when it is already a custom view, a spacer or a system item.
        private func floatingItem(for item: UIBarButtonItem) -> UIBarButtonItem {
            if floatingItems.contains(ObjectIdentifier(item)) || item.customView != nil {
                return item
            }
            let button: UIButton
            if let image = item.image {
                button = FloatingIconButton(image: image.applyingSymbolConfiguration(FloatingChrome.iconConfiguration) ?? image)
            } else if let title = item.title, !title.isEmpty {
                button = FloatingTextButton(title: title, isConfirming: item.style == .done)
            } else {
                return item
            }
            button.accessibilityLabel = item.accessibilityLabel ?? item.title
            button.isEnabled = item.isEnabled
            button.menu = item.menu
            button.showsMenuAsPrimaryAction = item.menu != nil && item.primaryAction == nil && item.action == nil

            let wrapped = barItem(wrapping: button)
            wrapped.accessibilityLabel = button.accessibilityLabel
            if let primaryAction = item.primaryAction {
                button.addAction(UIAction { [weak wrapped] _ in
                    primaryAction.performWithSender(wrapped, target: nil)
                }, for: .touchUpInside)
            } else if let action = item.action {
                button.addAction(UIAction { [weak wrapped, weak target = item.target] _ in
                    UIApplication.shared.sendAction(action, to: target, from: wrapped, for: nil)
                }, for: .touchUpInside)
            }

            // Pages enable, disable and re-menu their items later.
            let observations = [
                item.observe(\.isEnabled, options: [.new]) { [weak button] item, _ in
                    MainActor.assumeIsolated { button?.isEnabled = item.isEnabled }
                },
                item.observe(\.menu, options: [.new]) { [weak button] item, _ in
                    MainActor.assumeIsolated { button?.menu = item.menu }
                },
            ]
            replacedItems[ObjectIdentifier(wrapped)] = (item, observations)
            return wrapped
        }

        private func barItem(wrapping button: UIButton) -> UIBarButtonItem {
            let surface = button.wrappedInFloatingButtonSurface()
            surface.snp.makeConstraints { make in
                make.height.equalTo(FloatingChrome.buttonSize)
                if button is FloatingIconButton {
                    make.width.equalTo(FloatingChrome.buttonSize)
                }
            }
            let item = UIBarButtonItem(customView: surface)
            if #available(iOS 26, *) {
                // Only reached with the debug switch on: keep the system's
                // shared glass from wrapping the material surface again.
                item.hidesSharedBackground = true
            }
            floatingItems.insert(ObjectIdentifier(item))
            return item
        }
    #endif
}

#if !targetEnvironment(macCatalyst)
    extension FadeBarNavigationController: UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === interactivePopGestureRecognizer else { return true }
            return viewControllers.count > 1 && transitionCoordinator == nil
        }
    }
#endif
