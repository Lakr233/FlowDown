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
      currentMessageListView != nil
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

    completion(true)

    session.doInfere(
      modelID: modelID,
      inputObject: object,
    ) {}

    #if targetEnvironment(macCatalyst)
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(500))
        self.editor.focus()
      }
    #endif
  }

  func onRichEditorVisualInputHint(
    attachments: [RichEditorView.Object.Attachment],
    modelIdentifier: String,
  ) -> String? {
    // With no model selected, sending asks the user to pick one instead.
    guard !modelIdentifier.isEmpty else { return nil }
    let modelCapabilities = ModelManager.shared.modelCapabilities(identifier: modelIdentifier)
    guard
      ConversationSession.hasImagesRequiringVisualInput(
        attachments,
        modelCapabilities: modelCapabilities,
      )
    else { return nil }
    return ConversationSession.visualInputUnsupportedHintText
  }

  func onRichEditorError(_ error: String) {
    Indicator.present(
      title: "\(error)",
      preset: .error,
      referencingView: self,
    )
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

  /// Every conversation chats on the global default. `Conversation.modelId`
  /// is kept for devices that have not upgraded and is not read here.
  func modelIdentifier() -> String? {
    ModelManager.ModelIdentifier.defaultModelForConversation
  }

  func onRichEditorRequestAutomaticModelSelection() {
    guard modelIdentifier()?.isEmpty ?? true else { return }

    guard let candidate = ModelManager.shared.automaticSelectionCandidate() else {
      Logger.model.infoFile("no model available for automatic selection")
      return
    }

    Logger.model.infoFile("automatically selected model: \(candidate)")
    ModelManager.ModelIdentifier.defaultModelForConversation = candidate
    editor.updateModelinfoFile()
    offloadModelsToSession(modelIdentifier: candidate)
  }

  func onRichEditorRequestCurrentModelName() -> String? {
    guard let modelIdentifier = modelIdentifier() else { return nil }
    if #available(iOS 26.0, macCatalyst 26.0, *),
      modelIdentifier == AppleIntelligenceModel.shared.modelIdentifier
    {
      return AppleIntelligenceModelNames.localModel
    }
    if modelIdentifier == PrivateCloudComputeCenter.modelIdentifier {
      return AppleIntelligenceModelNames.privateCloudComputeModel
    }
    if let localModel = ModelManager.shared.localModel(identifier: modelIdentifier) {
      return Self.modelButtonTitle(for: localModel.modelDisplayName)
    }
    if let cloudModel = ModelManager.shared.cloudModel(identifier: modelIdentifier) {
      return Self.modelButtonTitle(for: cloudModel.modelDisplayName)
    }
    return nil
  }

  /// The model button shows only the last path component of a model's name,
  /// or the full name when that component is empty.
  static func modelButtonTitle(for name: String) -> String {
    let lastComponent = name.split(separator: "/", omittingEmptySubsequences: false).last ?? ""
    let trimmed = lastComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? name : trimmed
  }

  func onRichEditorRequestCurrentModelIcon() -> UIImage? {
    guard modelIdentifier() == PrivateCloudComputeCenter.modelIdentifier else { return nil }
    // The same symbol as the Private Cloud Compute switch in Settings.
    return UIImage(systemName: "icloud")
  }

  func onRichEditorRequestCurrentModelIdentifier() -> String? {
    modelIdentifier()
  }

  func onRichEditorBuildModelSelectionMenu(completion: @escaping () -> Void) -> [UIMenuElement] {
    guard conversationIdentifier != nil else { return [] }
    return ModelManager.shared.buildModelSelectionMenu(
      currentSelection: modelIdentifier(),
      onCompletion: { modelIdentifier in
        ModelManager.ModelIdentifier.defaultModelForConversation = modelIdentifier
        completion()
      },
    )
  }

  func onRichEditorBuildAlternativeToolsMenu(
    isEnabled: Bool,
    requestReload: @escaping (Bool) -> Void
  ) -> [UIMenuElement] {
    let mcpServers = MCPService.shared.servers.value
    var toolMenuItems: [UIMenuElement] = [
      UIAction(
        title: String(localized: "Enabled"),
        image: UIImage(systemName: "hammer"),
        state: isEnabled ? .on : .off,
      ) { [weak self] _ in
        self?.applyToolsToggleChange(requestReload: requestReload)
      }
    ]

    func createAction(for tools: [any ConfigurableModelTool]) -> [UIAction] {
      tools.map { tool in
        UIAction(
          title: tool.interfaceName,
          image: .init(systemName: tool.interfaceIcon),
          attributes: [.keepsMenuPresented],
          state: tool.isEnabled ? .on : .off,
        ) { [weak self] _ in
          self?.applyToolSelectionChange(requestReload: requestReload) {
            tool.isEnabled.toggle()
            return tool.isEnabled
          }
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
          title: String(localized: "Calendar Tools"),
          image: UIImage(systemName: "calendar"),
          attributes: [.keepsMenuPresented],
          state: calendarToolsHasOneEnabled ? .on : .off,
        ) { [weak self] _ in
          self?.applyToolSelectionChange(requestReload: requestReload) {
            let target = !calendarTools.contains { $0.isEnabled }
            for tool in calendarTools {
              tool.isEnabled = target
            }
            return target
          }
        }
      ],
      [
        UIAction(
          title: String(localized: "Reminder Tools"),
          image: UIImage(systemName: "checklist"),
          attributes: [.keepsMenuPresented],
          state: reminderToolsHasOneEnabled ? .on : .off,
        ) { [weak self] _ in
          self?.applyToolSelectionChange(requestReload: requestReload) {
            let target = !reminderTools.contains { $0.isEnabled }
            for tool in reminderTools {
              tool.isEnabled = target
            }
            return target
          }
        }
      ],
      createAction(for: ModelToolsManager.shared.configurableTools),
      [
        UIAction(
          title: String(localized: "Memory Tools"),
          image: UIImage(systemName: "memorychip"),
          attributes: [.keepsMenuPresented],
          state: memoryToolsHasOneEnabled ? .on : .off,
        ) { [weak self] _ in
          self?.applyToolSelectionChange(requestReload: requestReload) {
            let target = !memoryTools.contains { $0.isEnabled }
            for tool in memoryTools {
              tool.isEnabled = target
            }
            return target
          }
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
        ) { [weak self] _ in
          self?.applyToolSelectionChange(requestReload: requestReload) {
            // The menu stays open between picks, so read the stored value.
            let target = !(MCPService.shared.server(with: server.id)?.isEnabled ?? server.isEnabled)
            MCPService.shared.edit(identifier: server.id) {
              $0.update(\.isEnabled, to: target)
            }
            return target
          }
        }
      }

      mcpActions.append(
        UIAction(
          title: String(localized: "Settings"),
          image: UIImage(systemName: "gear"),
        ) { [weak self] _ in
          SettingController.setNextEntryPage(.tools)
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

  func offloadModelsToSession(modelIdentifier: ModelManager.ModelIdentifier?) {
    guard let conversationIdentifier else {
      assertionFailure()
      return
    }
    let session = ConversationSessionManager.shared.session(for: conversationIdentifier)

    session.models.chat = modelIdentifier ?? .defaultModelForConversation

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
  }
}
