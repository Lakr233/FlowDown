//
//  SettingContent+Tools.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/22/25.
//

import AlertController
import ConfigurableKit
import Digger
import ScrubberKit
import Storage
import UIKit

extension SettingController.SettingContent {
  class ToolsController: StackScrollController {
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
    }

    override func setupContentViews() {
      super.setupContentViews()

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionHeaderView().with(
          header: "Web Search",
        ),
      ) { $0.bottom /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ModelManager.searchSensitivityConfigurableObject.createView(),
      )
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ScrubberConfiguration.limitConfigurableObject.createView(),
      )
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionFooterView().with(
          footer:
            "Pages that exceed the model's context length will be ignored. Too many pages may increase network usage and slow down inference.",
        ),
      ) { $0.top /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionHeaderView().with(
          header: "Web Search Engines",
        ),
      ) { $0.bottom /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ScrubberConfiguration.googleEnabledConfigurableObject.createView())
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ScrubberConfiguration.duckduckgoEnabledConfigurableObject.createView())
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ScrubberConfiguration.yahooEnabledConfigurableObject.createView())
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ScrubberConfiguration.bingEnabledConfigurableObject.createView())
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionFooterView().with(
          footer: "You must enable at least one search engine for web search to work properly.",
        ),
      ) { $0.top /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      stackView.addArrangedSubviewWithMargin(
        ConfigurableSectionHeaderView().with(
          header: "Tool Call",
        ),
      ) { $0.bottom /= 2 }
      stackView.addArrangedSubview(SeparatorView())

      let mcpObject = ConfigurableObject(
        icon: "server.rack",
        title: "MCP Tools",
        explain: "Manage tools provided by MCP servers.",
        ephemeralAnnotation: .page { MCPController() },
      )
      stackView.addArrangedSubviewWithMargin(mcpObject.createView())
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
            "When this is off, tools run without asking, including ones that change your calendar or reminders. Web search, reading web pages, and memory never ask.",
        ),
      ) { $0.top /= 2 }
      stackView.addArrangedSubview(SeparatorView())
    }
  }
}
