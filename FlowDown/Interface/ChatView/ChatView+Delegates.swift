//
//  ChatView+Delegates.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import RegexBuilder
import ScrubberKit
import Storage
import UIKit

extension ChatView: RichEditorView.Delegate {
  func onRichEditorSubmit(object: RichEditorView.Object, completion: @escaping (Bool) -> Void) {
    guard let conversationID = conversationIdentifier,
      let currentMessageListView
    else {
      assertionFailure()
      return
    }

    guard let modelID = modelIdentifier(), !modelID.isEmpty else {
      if ModelManager.shared.localModels.value.isEmpty,
        ModelManager.shared.cloudModels.value.isEmpty
      {
        let alert = AlertViewController(
          title: "Error",
          message: "You need to add a model to use.",
        ) { context in
          context.allowSimpleDispose()
          context.addAction(title: "Cancel") {
            context.dispose()
          }
          context.addAction(title: "Add Model", attribute: .accent) {
            context.dispose {
              SettingController.setNextEntryPage(.modelManagement)
              let setting = SettingController()
              self.parentViewController?.present(setting, animated: true)
            }
          }
        }
        parentViewController?.present(alert, animated: true)
      } else {
        let alert = AlertViewController(
          title: "Error",
          message: "You need to select a model to use.",
        ) { context in
          context.allowSimpleDispose()
          context.addAction(title: "OK", attribute: .accent) {
            context.dispose()
          }
        }
        parentViewController?.present(alert, animated: true)
      }
      completion(false)
      return
    }

    let session = ConversationSessionManager.shared.session(for: conversationID)
    offloadModelsToSession(modelIdentifier: modelIdentifier())
    if case .bool(let value) = object.options[.browsing], value {
      guard let auxModel = session.models.auxiliary,
        !auxModel.isEmpty
      else {
        let alert = AlertViewController(
          title: "Error",
          message: "A tool model is required for browsing.",
        ) { context in
          context.allowSimpleDispose()
          context.addAction(title: "Close") {
            context.dispose()
          }
          context.addAction(title: "Configure", attribute: .accent) {
            context.dispose { [weak self] in
              SettingController.setNextEntryPage(.inference)
              let setting = SettingController()
              self?.parentViewController?.present(setting, animated: true)
            }
          }
        }
        parentViewController?.present(alert, animated: true)
        completion(false)
        return
      }
    }

    let shouldHaveVisualModel = object.attachments.contains { $0.type == .image }
    if shouldHaveVisualModel {
      let currentModelCanSee = ModelManager.shared.modelCapabilities(identifier: modelID)
        .contains(.visual)
      let auxModelExists = !(session.models.visualAuxiliary?.isEmpty ?? true)
      guard currentModelCanSee || auxModelExists else {
        let alert = AlertViewController(
          title: "Error",
          message: "A visual model is required for image attachments.",
        ) { context in
          context.allowSimpleDispose()
          context.addAction(title: "Close") {
            context.dispose()
          }
          context.addAction(title: "Configure", attribute: .accent) {
            context.dispose { [weak self] in
              SettingController.setNextEntryPage(.inference)
              let setting = SettingController()
              SettingController.setNextEntryPage(.modelManagement)
              self?.parentViewController?.present(setting, animated: true)
            }
          }
        }
        parentViewController?.present(alert, animated: true)
        completion(false)
        return
      }
    }

    completion(true)

    session.doInfere(
      modelID: modelID,
      currentMessageListView: currentMessageListView,
      inputObject: object,
    ) {}

    #if targetEnvironment(macCatalyst)
      Task { @MainActor in
        try await Task.sleep(for: .milliseconds(500))
        self.editor.focus()
      }
    #endif
  }

  func onRichEditorError(_ error: String) {
    Indicator.present(
      title: "\(error)",
      preset: .error,
      referencingView: self,
    )
  }

  func onRichEditorTogglesUpdate(object: RichEditorView.Object) {
    _ = object
  }

  func onRichEditorRequestObjectForRestore() -> RichEditorView.Object? {
    guard let conversationIdentifier else { return nil }
    return ConversationManager.shared.getRichEditorObject(identifier: conversationIdentifier)
  }

  func onRichEditorUpdateObject(object: RichEditorView.Object) {
    guard let conversationIdentifier else { return }
    ConversationManager.shared.setRichEditorObject(identifier: conversationIdentifier, object)
    offloadModelsToSession(modelIdentifier: modelIdentifier())
  }

  func modelIdentifier() -> String? {
    if let id = ConversationManager.shared.conversation(
      identifier: conversationIdentifier,
    )?.modelId {
      return id
    }
    return ModelManager.ModelIdentifier.defaultModelForConversation
  }

  func onRichEditorRequestCurrentModelName() -> String? {
    guard let modelIdentifier = modelIdentifier() else { return nil }
    if #available(iOS 26.0, macCatalyst 26.0, *),
      modelIdentifier == AppleIntelligenceModel.shared.modelIdentifier
    {
      return AppleIntelligenceModel.shared.modelDisplayName
    }
    if let localModel = ModelManager.shared.localModel(identifier: modelIdentifier) {
      switch editorModelNameStyle {
      case .full: return localModel.model_identifier
      case .trimmed: return localModel.modelDisplayName
      case .none: return "👌"
      }
    } else if let cloudModel = ModelManager.shared.cloudModel(identifier: modelIdentifier) {
      switch editorModelNameStyle {
      case .full: return cloudModel.modelFullName
      case .trimmed: return cloudModel.modelDisplayName
      case .none: return "👌"
      }
    }
    return nil
  }

  func onRichEditorRequestCurrentModelIdentifier() -> String? {
    modelIdentifier()
  }

  func onRichEditorBuildModelSelectionMenu(completion: @escaping () -> Void) -> [UIMenuElement] {
    guard let conversationIdentifier else { return [] }
    let modelIdentifier = ConversationManager.shared.conversation(
      identifier: conversationIdentifier,
    )?.modelId
    return ModelManager.shared.buildModelSelectionMenu(
      currentSelection: modelIdentifier,
      onCompletion: { modelIdentifier in
        ConversationManager.shared.editConversation(identifier: conversationIdentifier) {
          $0.update(\.modelId, to: modelIdentifier)
        }
        if self.editorApplyModelToDefault {
          ModelManager.ModelIdentifier.defaultModelForConversation = modelIdentifier
        }
        completion()
      },
      includeQuickActions: true,
    )
  }

  func onRichEditorBuildAlternativeModelMenu() -> [UIMenuElement] {
    let isAppleIntelligence: Bool = {
      guard let id = modelIdentifier(), !id.isEmpty else { return false }
      if #available(iOS 26.0, macCatalyst 26.0, *) {
        return id == AppleIntelligenceModel.shared.modelIdentifier
      }
      return false
    }()
    return [
      { () -> UIAction? in
        guard !isAppleIntelligence, let id = modelIdentifier(), !id.isEmpty else { return nil }
        return UIAction(
          title: String(localized: "Edit Model"),
          image: UIImage(systemName: "slider.horizontal.3"),
        ) { [weak self] _ in
          SettingController.setNextEntryPage(.modelEditor(model: id))
          let settingController = SettingController()
          self?.parentViewController?.present(settingController, animated: true)
        }
      }(),
      UIAction(
        title: String(localized: "Inference Settings"),
        image: UIImage(systemName: "gearshape"),
      ) { [weak self] _ in
        SettingController.setNextEntryPage(.inference)
        let settingController = SettingController()
        self?.parentViewController?.present(settingController, animated: true)
      },
    ].compactMap(\.self)
  }

  func onRichEditorBuildAlternativeToolsMenu(
    isEnabled: Bool, requestReload: @escaping (Bool) -> Void
  ) -> [UIMenuElement] {
    let mcpServers = MCPService.shared.servers.value
    var toolMenuItems: [UIMenuElement] = [
      UIAction(
        title: String(localized: "Enabled"),
        image: UIImage(systemName: "hammer"),
        state: isEnabled ? .on : .off,
      ) { _ in
        requestReload(!isEnabled)
      }
    ]

    func createAction(for tools: [ModelTool]) -> [UIAction] {
      tools.map { tool in
        UIAction(
          title: tool.interfaceName,
          image: .init(systemName: tool.interfaceIcon),
          attributes: [.keepsMenuPresented],
          state: tool.isEnabled ? .on : .off,
        ) { _ in
          tool.isEnabled.toggle()
          requestReload(isEnabled)
        }
      }
    }

    let memoryTools = ModelToolsManager.shared.memoryTools
    let memoryToolsHasOneEnabled = memoryTools.contains { $0.isEnabled }

    let calendarTools = ModelToolsManager.shared.calendarTools
    let calendarToolsHasOneEnabled = calendarTools.contains { $0.isEnabled }

    let reminderTools = ModelToolsManager.shared.reminderTools
    let reminderToolsHasOneEnabled = reminderTools.contains { $0.isEnabled }

    let builtin: [UIAction] = [
      [
        UIAction(
          title: String(localized: "Calendar"),
          image: UIImage(systemName: "calendar"),
          attributes: [.keepsMenuPresented],
          state: calendarToolsHasOneEnabled ? .on : .off,
        ) { _ in
          let target = !calendarToolsHasOneEnabled
          for tool in calendarTools {
            tool.isEnabled = target
          }
          requestReload(isEnabled)
        }
      ],
      [
        UIAction(
          title: String(localized: "Reminders"),
          image: UIImage(systemName: "checklist"),
          attributes: [.keepsMenuPresented],
          state: reminderToolsHasOneEnabled ? .on : .off,
        ) { _ in
          let target = !reminderToolsHasOneEnabled
          for tool in reminderTools {
            tool.isEnabled = target
          }
          requestReload(isEnabled)
        }
      ],
      createAction(for: ModelToolsManager.shared.configurableTools),
      [
        UIAction(
          title: String(localized: "Memory Tools"),
          image: UIImage(systemName: "memorychip"),
          attributes: [.keepsMenuPresented],
          state: memoryToolsHasOneEnabled ? .on : .off,
        ) { _ in
          let target = !memoryToolsHasOneEnabled
          for tool in memoryTools {
            tool.isEnabled = target
          }
          requestReload(isEnabled)
        }
      ],
    ].flatMap(\.self)

    toolMenuItems.append(
      UIMenu(
        title: String(localized: "Built-in Tools"),
        options: [.displayInline],
        children: builtin,
      ))

    if !mcpServers.isEmpty {
      var mcpActions: [UIMenuElement] = mcpServers.map { server in
        let name =
          server.name.isEmpty
          ? URL(string: server.endpoint)?.host ?? String(localized: "Unknown Server")
          : server.name
        return UIAction(
          title: name,
          image: UIImage(systemName: "server.rack"),
          attributes: [.keepsMenuPresented],
          state: server.isEnabled ? .on : .off,
        ) { _ in
          MCPService.shared.edit(identifier: server.id) {
            $0.update(\.isEnabled, to: !$0.isEnabled)
          }
          requestReload(isEnabled)
        }
      }

      mcpActions.append(
        UIAction(
          title: String(localized: "Settings"),
          image: UIImage(systemName: "gear"),
        ) { [weak self] _ in
          SettingController.setNextEntryPage(.mcp)
          let settingController = SettingController()
          self?.parentViewController?.present(settingController, animated: true)
        },
      )

      toolMenuItems.append(
        UIMenu(
          title: String(localized: "MCP Servers"),
          options: mcpServers.count < 5 ? [.displayInline] : [],
          children: mcpActions,
        ))
    }

    return toolMenuItems
  }

  func onRichEditorCheckIfModelSupportsToolCall(_ modelIdentifier: String) -> Bool {
    ModelManager.shared.modelCapabilities(identifier: modelIdentifier).contains(.tool)
  }

  func onSelectLocalModel(_ model: LocalModel) {
    onSelectModel(model_id: model.id)
  }

  func onSelectCloudModel(_ model: CloudModel) {
    onSelectModel(model_id: model.id)
  }

  private func onSelectModel(model_id: String) {
    offloadModelsToSession(modelIdentifier: model_id)
  }

  func offloadModelsToSession(modelIdentifier: ModelManager.ModelIdentifier?) {
    guard let conversationIdentifier else {
      assertionFailure()
      return
    }
    let session = ConversationSessionManager.shared.session(for: conversationIdentifier)

    session.models.chat = modelIdentifier ?? .defaultModelForConversation
    if ModelManager.ModelIdentifier.defaultModelForAuxiliaryTaskWillUseCurrentChatModel {
      session.models.auxiliary = session.models.chat ?? .defaultModelForAuxiliaryTask
    } else {
      session.models.auxiliary = ModelManager.ModelIdentifier.defaultModelForAuxiliaryTask
    }
    session.models.visualAuxiliary = ModelManager.ModelIdentifier.defaultModelForAuxiliaryVisualTask

    NSObject.cancelPreviousPerformRequests(withTarget: self)
    perform(#selector(printModelInfomation), with: nil, afterDelay: 0.25)
  }

  @objc func printModelInfomation() {
    guard let conversationIdentifier else { return }
    let session = ConversationSessionManager.shared.session(for: conversationIdentifier)
    Logger.model.infoFile("offloaded model to session: \(conversationIdentifier)")
    Logger.model.debugFile(
      "chat: \(ModelManager.shared.modelName(identifier: session.models.chat))")
    Logger.model.debugFile(
      "task: \(ModelManager.shared.modelName(identifier: session.models.auxiliary))")
    Logger.model.debugFile(
      "view: \(ModelManager.shared.modelName(identifier: session.models.visualAuxiliary))")
  }
}
