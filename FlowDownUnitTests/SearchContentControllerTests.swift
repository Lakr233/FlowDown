@testable import FlowDown
import Foundation
import Storage
import Testing
import UIKit

struct SearchContentControllerTests {
    @MainActor
    private func makeController() -> SearchContentController {
        let controller = SearchContentController { _ in }
        controller.loadViewIfNeeded()
        controller.searchResults = ["First", "Second"].map { title in
            let conversation = Conversation(deviceId: Storage.deviceId)
            conversation.update(\.title, to: title)
            return ConversationSearchResult(
                conversation: conversation,
                matchType: .title,
                matchedText: title,
            )
        }
        return controller
    }

    @MainActor
    private func keyCommand(
        _ input: String,
        on searchBar: KeyboardNavigationSearchBar,
    ) throws -> UIKeyCommand {
        let command = try #require(searchBar.keyCommands?.first(where: { $0.input == input }))
        // Without priority the search field spends the arrow on its caret.
        #expect(command.wantsPriorityOverSystemBehavior)
        return command
    }

    @Test
    @MainActor
    func searchContent_downArrow_highlightsFirstResult() throws {
        let controller = makeController()
        let searchBar = try #require(controller.searchBar as? KeyboardNavigationSearchBar)
        let delegate = searchBar.keyboardNavigationDelegate as? SearchContentController
        #expect(delegate === controller)

        let command = try keyCommand(UIKeyCommand.inputDownArrow, on: searchBar)
        let downArrow = try #require(command.action)
        _ = searchBar.perform(downArrow)
        #expect(controller.focusedIndexPath == IndexPath(row: 0, section: 0))
        _ = searchBar.perform(downArrow)
        #expect(controller.focusedIndexPath == IndexPath(row: 1, section: 0))
    }

    @Test
    @MainActor
    func searchContent_upArrow_movesHighlightBack() throws {
        let controller = makeController()
        let searchBar = try #require(controller.searchBar as? KeyboardNavigationSearchBar)

        let command = try keyCommand(UIKeyCommand.inputUpArrow, on: searchBar)
        let upArrow = try #require(command.action)
        _ = searchBar.perform(upArrow)
        #expect(controller.focusedIndexPath == IndexPath(row: 1, section: 0))
        _ = searchBar.perform(upArrow)
        #expect(controller.focusedIndexPath == IndexPath(row: 0, section: 0))
    }
}
