@preconcurrency @testable import FlowDown
import Foundation
import Storage
import SwiftUI
import Testing
import UIKit

/// Guards the chat page's own soft edges on the wide layout (sidebar beside
/// the chat: iPad, an open iPhone Duo). A build that let the system draw
/// these edges showed an opaque white bar with a hairline under the header
/// and above the input instead of our `ProgressiveBlurView`s (#350, undone
/// by #362). These checks run against a live `MainController`.
@Suite(.serialized)
struct WideLayoutEdgeBlurTests {
    @Test
    func floatingChrome_neverUsesSystemScrollEdge() {
        #expect(!FloatingChrome.usesSystemScrollEdge)
    }

    #if !targetEnvironment(macCatalyst)
        @Test
        @MainActor
        func wideLayout_chatPage_drawsOwnEdgeBlurs_withoutSystemBarOrHairline() async throws {
            try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

            let conversation = sdb.conversationMake { conversation in
                conversation.update(\.title, to: "Edge Blur \(UUID().uuidString.prefix(8))")
            }
            ConversationManager.shared.scanAll()
            defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }

            // Open the sidebar beside the chat; leave the user's choice as found.
            let key = MainController.sidebarCollapsedKey
            let storedCollapsed = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.set(false, forKey: key)
            defer { UserDefaults.standard.set(storedCollapsed, forKey: key) }

            let host = UIViewController()
            host.traitOverrides.horizontalSizeClass = .regular
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1194, height: 834))
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            let main = MainController()
            main.hasScheduledWelcome = true
            host.addChild(main)
            main.view.frame = host.view.bounds
            host.view.addSubview(main.view)
            main.didMove(toParent: host)
            main.view.layoutIfNeeded()

            #expect(main.currentSidebarPresentation == .persistent)
            #expect(!main.isSidebarCollapsed)

            main.load(conversation.id)
            main.view.setNeedsLayout()
            main.view.layoutIfNeeded()

            let chatView = main.chatView
            chatView.layoutIfNeeded()
            #expect(chatView.bounds.width > 0)
            #expect(chatView.bounds.width < main.view.bounds.width, "the sidebar stands beside the chat")

            let listView = try #require(chatView.currentMessageListView)
            #expect(listView.superview === chatView)

            // Top: our blur from the top of the page past the header buttons,
            // over the messages and under the header controls.
            let topBlur = try #require(chatView.topEdgeBlur, "the chat's own top blur is gone")
            topBlur.layoutIfNeeded()
            let button = chatView.escapeButton.convert(chatView.escapeButton.bounds, to: chatView)
            #expect(topBlur.superview === chatView)
            #expect(topBlur.edge == .top)
            #expect(!topBlur.isHidden && topBlur.alpha == 1)
            #expect(topBlur.frame.minY == 0)
            #expect(topBlur.frame.minX == 0 && topBlur.frame.width == chatView.bounds.width)
            #expect(topBlur.frame.maxY > button.maxY)
            #expect(isDrawingBlur(topBlur))
            #expect(isTransparent(topBlur.backgroundColor))
            #expect(index(of: listView, in: chatView) < index(of: topBlur, in: chatView))
            #expect(index(of: topBlur, in: chatView) < index(of: chatView.title, in: chatView))

            // Above the input: our blur fading from the card's centre line to
            // `tail` above the card, also over the messages.
            let bottomBlur = chatView.bottomEdgeBlur
            bottomBlur.layoutIfNeeded()
            let card = chatView.editor.convert(chatView.editor.shadowContainer.frame, to: chatView)
            #expect(bottomBlur.superview === chatView)
            #expect(bottomBlur.edge == .bottom)
            #expect(!bottomBlur.isHidden && bottomBlur.alpha == 1)
            #expect(bottomBlur.frame.height > 0)
            #expect(abs(bottomBlur.frame.minY - (card.minY - FloatingChrome.tail)) < 0.5)
            #expect(abs(bottomBlur.frame.maxY - card.midY) < 0.5)
            #expect(bottomBlur.frame.width == chatView.bounds.width)
            #expect(isDrawingBlur(bottomBlur))
            #expect(isTransparent(bottomBlur.backgroundColor))
            #expect(index(of: listView, in: chatView) < index(of: bottomBlur, in: chatView))

            // The system's own scroll edges stay off, or they stack with ours
            // and draw the opaque bar.
            if #available(iOS 26, *) {
                #expect(listView.listView.topEdgeEffect.isHidden, "system top scroll edge effect is on")
                #expect(listView.listView.bottomEdgeEffect.isHidden, "system bottom scroll edge effect is on")
            }

            // No bar background or hairline of its own across either band.
            #expect(isTransparent(chatView.title.backgroundColor))
            #expect(isTransparent(chatView.editorBackgroundView.backgroundColor))
            let topBand = CGRect(x: 0, y: 0, width: chatView.bounds.width, height: topBlur.frame.maxY)
            let bottomBand = bottomBlur.frame
            for (name, band) in [("top", topBand), ("input", bottomBand)] {
                let offenders = barLikeViews(in: chatView, crossing: band, skipping: [listView, topBlur, bottomBlur])
                #expect(offenders.isEmpty, "\(name) edge is covered by \(offenders)")
            }
            #expect(main.navigationController == nil)
        }

        /// Whether the view still renders a backdrop blur, not a plain fill.
        @MainActor
        private func isDrawingBlur(_ view: ProgressiveBlurView) -> Bool {
            let backdrops = (view.layer.sublayers ?? []).filter {
                NSStringFromClass(type(of: $0)).contains("BackdropLayer")
            }
            return !backdrops.isEmpty && backdrops.allSatisfy { !($0.filters ?? []).isEmpty }
        }

        private func isTransparent(_ color: UIColor?) -> Bool {
            guard let color else { return true }
            var alpha: CGFloat = 0
            color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            return alpha < 0.01
        }

        @MainActor
        private func index(of view: UIView, in superview: UIView) -> Int {
            var current: UIView? = view
            while let candidate = current, candidate.superview !== superview {
                current = candidate.superview
            }
            guard let current else { return -1 }
            return superview.subviews.firstIndex(of: current) ?? -1
        }

        /// Visible views running the page's full width through `band` that
        /// paint a bar: a navigation bar or toolbar, an opaque fill, a
        /// material blur, or a hairline.
        @MainActor
        private func barLikeViews(in root: UIView, crossing band: CGRect, skipping skipped: [UIView]) -> [String] {
            var found: [String] = []
            func visit(_ view: UIView) {
                guard !view.isHidden, view.alpha > 0.01, !skipped.contains(where: { $0 === view }) else { return }
                let frame = view.convert(view.bounds, to: root)
                if view !== root,
                   frame.width >= root.bounds.width - 1,
                   frame.intersects(band),
                   frame.intersection(band).height > 0
                {
                    let isBar = view is UINavigationBar || view is UIToolbar
                    let isFill = !isTransparent(view.backgroundColor)
                    let isMaterial = (view as? UIVisualEffectView)?.effect is UIBlurEffect
                    if isBar || isFill || isMaterial {
                        found.append("\(type(of: view)) \(frame)")
                    }
                }
                view.subviews.forEach(visit)
            }
            visit(root)
            return found
        }
    #endif
}
