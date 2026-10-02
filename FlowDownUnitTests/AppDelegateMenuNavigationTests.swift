//
//  AppDelegateMenuNavigationTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import Storage
import Testing

struct AppDelegateMenuNavigationTests {
    @Test
    @MainActor
    func sidebarOrderedIdentifiers_favoriteExists_putsFavoritesFirst() {
        // Storage order is creation descending: newest first.
        let newest = Conversation(deviceId: "test")
        let middle = Conversation(deviceId: "test")
        let oldestFavorite = Conversation(deviceId: "test")
        oldestFavorite.update(\.isFavorite, to: true)

        let order = AppDelegate.sidebarOrderedIdentifiers([newest, middle, oldestFavorite])

        // The sidebar shows the favorite first, so Next from it must reach
        // the newest conversation and Previous from that must come back.
        #expect(order == [oldestFavorite.id, newest.id, middle.id])
    }

    @Test
    @MainActor
    func sidebarOrderedIdentifiers_noFavorites_keepsStorageOrder() {
        let conversations = (0 ..< 3).map { _ in Conversation(deviceId: "test") }
        #expect(AppDelegate.sidebarOrderedIdentifiers(conversations) == conversations.map(\.id))
    }
}
