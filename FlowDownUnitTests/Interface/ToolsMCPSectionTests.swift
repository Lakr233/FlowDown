//
//  ToolsMCPSectionTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Testing
import UIKit

@MainActor
struct ToolsMCPSectionTests {
    typealias ToolsController = SettingController.SettingContent.ToolsController

    @Test
    func toolsEntryPage_opensToolsPage() {
        #expect(SettingController.EntryPage.tools.controller is ToolsController)
    }

    @Test
    func listItems_noServers_showsOnlyAddRow() {
        #expect(ToolsController.mcpListItems(for: []) == [.addServer])
    }

    @Test
    func listItems_withServers_keepsServiceOrderWithoutAddRow() {
        #expect(ToolsController.mcpListItems(for: ["b", "a"]) == [.server("b"), .server("a")])
    }

    @Test
    func emptyList_addRowDoesNotSwipe() {
        let controller = ToolsController()
        controller.loadViewIfNeeded()
        controller.applyMCPServers([])

        let tableView = controller.mcpTableView
        #expect(controller.mcpDataSource.snapshot().itemIdentifiers == [.addServer])
        let indexPath = IndexPath(row: 0, section: 0)
        #expect(!controller.mcpDataSource.tableView(tableView, canEditRowAt: indexPath))
        #expect(controller.tableView(tableView, trailingSwipeActionsConfigurationForRowAt: indexPath) == nil)
    }

    @Test
    func serverRow_swipeShowsDeleteWithoutFullSwipe() throws {
        let controller = ToolsController()
        controller.loadViewIfNeeded()
        controller.applyMCPServers(["first", "second"])

        let tableView = controller.mcpTableView
        let indexPath = IndexPath(row: 1, section: 0)
        #expect(controller.mcpDataSource.snapshot().itemIdentifiers == [.server("first"), .server("second")])
        #expect(controller.mcpDataSource.tableView(tableView, canEditRowAt: indexPath))
        let configuration = try #require(
            controller.tableView(tableView, trailingSwipeActionsConfigurationForRowAt: indexPath),
        )
        #expect(!configuration.performsFirstActionWithFullSwipe)
        #expect(configuration.actions.count == 1)
        #expect(configuration.actions.first?.style == .destructive)
        #expect(controller.tableView(tableView, leadingSwipeActionsConfigurationForRowAt: indexPath) == nil)
    }

    @Test
    func toolsPage_hasAddButtonInNavigationBar() {
        let controller = ToolsController()
        controller.loadViewIfNeeded()
        let item = controller.navigationItem.rightBarButtonItem
        #expect(item?.menu != nil)
        #expect(item?.accessibilityLabel == String(localized: "Add MCP Server"))
    }
}
