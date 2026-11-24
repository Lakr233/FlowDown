//
//  SettingContent+Tools.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/22/25.
//

import AlertController
import Combine
import ConfigurableKit
import Digger
import Storage
import UIKit

extension SettingController.SettingContent {
  class ToolsController: StackScrollController {
    /// The MCP server rows. A system table so the rows swipe, rubber-band
    /// and show their Delete button exactly like any other list; it does not
    /// scroll on its own and is as tall as its rows inside the page.
    let mcpTableView = MCPServerListView(frame: .zero, style: .plain)
    lazy var mcpDataSource: MCPDataSource = makeMCPDataSource()
    var mcpCancellables: Set<AnyCancellable> = []

    init() {
      super.init(nibName: nil, bundle: nil)
      title = String(localized: "Tools")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
      fatalError()
    }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .background

      let addItem = UIBarButtonItem(
        title: nil,
        image: UIImage(systemName: "plus"),
        primaryAction: nil,
        menu: UIMenu(children: createAddClientMenuItems()),
      )
      addItem.accessibilityLabel = String(localized: "Add MCP Server")
      navigationItem.rightBarButtonItem = addItem

      MCPService.shared.servers
        .ensureMainThread()
        .sink { [weak self] servers in
          self?.applyMCPServers(servers.map(\.id))
        }
        .store(in: &mcpCancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      MCPService.shared.updateFromDatabase()
    }

    override func setupContentViews() {
      super.setupContentViews()

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionHeaderView().with(
          header: "MCP Servers",
        ),
      ) { $0.bottom /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      // Each row draws its own separator below it.
      configureMCPTableView()
      stackView.addArrangedSubview(mcpTableView)

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionHeaderView().with(
          header: "Built-in Tools",
        ),
      ) { $0.bottom /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(ModelToolsManager.calendarToggle)
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(ModelToolsManager.remindersToggle)
      stackView.addArrangedSubview(SeparatorView())

      for tool in ModelToolsManager.shared.configurableTools {
        stackView.addArrangedSubviewWithMargin(tool.createConfigurableObjectView())
        stackView.addArrangedSubview(SeparatorView())
      }

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionFooterView().with(
          footer:
            "These tools can only be used by models that support tool calls, and whether to use them is determined by the model.",
        ),
      ) { $0.top /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionHeaderView().with(
          header: "Authorization",
        ),
      ) { $0.bottom /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(ModelToolAuthorization.configurableObject.createView())
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionFooterView().with(
          footer:
            "When this is off, tools run without asking, including ones that change your calendar or reminders. Reading web pages and memory never ask.",
        ),
      ) { $0.top /= 2 }
      stackView.addArrangedSubview(SeparatorView())
    }
  }
}
