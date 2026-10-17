@testable import FlowDown
import Testing
import UIKit

struct SidebarPersistenceTests {
    @Test
    @MainActor
    func sidebarPersistence_narrowLandscapeWindow_isDrawer() {
        // Slide Over or a one third Split View on an iPad held in landscape.
        let size = CGSize(width: 320, height: 1024)
        #expect(!MainController.allowsSidebarPersistence(horizontalSizeClass: .compact, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_wideLandscape_persists() {
        let size = CGSize(width: 1180, height: 820)
        #expect(MainController.allowsSidebarPersistence(horizontalSizeClass: .regular, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_widePortrait_persists() {
        let size = CGSize(width: 820, height: 1180)
        #expect(MainController.allowsSidebarPersistence(horizontalSizeClass: .regular, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_narrowPortrait_isDrawer() {
        let size = CGSize(width: 744, height: 1133)
        #expect(!MainController.allowsSidebarPersistence(horizontalSizeClass: .regular, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_belowDrawerWidth_neverPersists() {
        // Wider than tall, yet narrow enough for the drawer layout.
        let size = CGSize(width: 480, height: 320)
        #expect(!MainController.allowsSidebarPersistence(horizontalSizeClass: .regular, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_compactWidth_neverPersists() {
        // An iPhone held in landscape keeps a compact width however wide it is.
        let size = CGSize(width: 852, height: 393)
        #expect(!MainController.allowsSidebarPersistence(horizontalSizeClass: .compact, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_unspecifiedSizeClass_neverPersists() {
        // Before the window settles its traits.
        let size = CGSize(width: 1180, height: 820)
        #expect(!MainController.allowsSidebarPersistence(horizontalSizeClass: .unspecified, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_foldableInnerLandscape_persists() {
        // A foldable iPhone opened flat keeps the phone idiom at regular width.
        let size = CGSize(width: 871, height: 669)
        #expect(MainController.allowsSidebarPersistence(horizontalSizeClass: .regular, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_foldableInnerPortrait_isDrawer() {
        let size = CGSize(width: 669, height: 871)
        #expect(!MainController.allowsSidebarPersistence(horizontalSizeClass: .regular, size: size))
    }

    @Test
    @MainActor
    func sidebarLayout_phoneWidth_usesDrawer() {
        // The narrowest and widest iPhone in portrait, and a closed foldable.
        for width: CGFloat in [320, 440, 386] {
            #expect(MainController.usesDrawerLayout(width: width))
        }
    }

    @Test
    @MainActor
    func sidebarLayout_foldableInnerWidth_usesSidebar() {
        for width: CGFloat in [871, 669] {
            #expect(!MainController.usesDrawerLayout(width: width))
        }
    }

    @Test
    @MainActor
    func sidebarFoldSplit_centredFold_endsSidebarAtFold() {
        // The inner display of a foldable half open, with a zero-width fold.
        let fold = CGRect(x: 475.5, y: 0, width: 0, height: 669)
        let split = MainController.sidebarSplit(
            fold: fold,
            sidebarMinX: 20,
            minimumWidth: 200,
            maximumWidth: 512,
        )
        #expect(split == MainController.SidebarFoldSplit(sidebarWidth: 435.5, chatSpacing: 20))
    }

    @Test
    @MainActor
    func sidebarFoldSplit_wideFold_startsChatPastFold() {
        let fold = CGRect(x: 470, y: 0, width: 12, height: 669)
        let split = MainController.sidebarSplit(
            fold: fold,
            sidebarMinX: 54,
            minimumWidth: 200,
            maximumWidth: 512,
        )
        #expect(split?.sidebarWidth == 396)
        // Sidebar trailing edge plus the spacing lands on the fold's far edge.
        #expect(split.map { 54 + $0.sidebarWidth + $0.chatSpacing } == 482)
    }

    @Test
    @MainActor
    func sidebarFoldSplit_foldOutOfRange_keepsUserWidth() {
        let nearLeading = CGRect(x: 150, y: 0, width: 0, height: 669)
        let nearTrailing = CGRect(x: 800, y: 0, width: 0, height: 669)
        for fold in [nearLeading, nearTrailing] {
            #expect(MainController.sidebarSplit(
                fold: fold,
                sidebarMinX: 20,
                minimumWidth: 200,
                maximumWidth: 512,
            ) == nil)
        }
    }
}
