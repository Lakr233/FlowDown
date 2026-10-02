@testable import FlowDown
import Testing
import UIKit

struct SidebarPersistenceTests {
    @Test
    @MainActor
    func sidebarPersistence_narrowLandscapeWindow_isDrawer() {
        // Slide Over or a one third Split View on an iPad held in landscape.
        let size = CGSize(width: 320, height: 1024)
        #expect(!MainController.allowsSidebarPersistence(idiom: .pad, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_wideLandscape_persists() {
        let size = CGSize(width: 1180, height: 820)
        #expect(MainController.allowsSidebarPersistence(idiom: .pad, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_widePortrait_persists() {
        let size = CGSize(width: 820, height: 1180)
        #expect(MainController.allowsSidebarPersistence(idiom: .pad, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_narrowPortrait_isDrawer() {
        let size = CGSize(width: 744, height: 1133)
        #expect(!MainController.allowsSidebarPersistence(idiom: .pad, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_belowDrawerWidth_neverPersists() {
        // Wider than tall, yet narrow enough for the drawer layout.
        let size = CGSize(width: 480, height: 320)
        #expect(!MainController.allowsSidebarPersistence(idiom: .pad, size: size))
    }

    @Test
    @MainActor
    func sidebarPersistence_phone_neverPersists() {
        let size = CGSize(width: 932, height: 430)
        #expect(!MainController.allowsSidebarPersistence(idiom: .phone, size: size))
    }
}
