//
//  ConversationSystemPromptBuilderTests.swift
//  FlowDownUnitTests
//
//  Created by GPT-5 Codex on 4/12/26.
//

@testable import ChatClientKit
import Foundation
import Testing

@testable import FlowDown

struct ConversationSystemPromptBuilderTests {
  struct MemoryExposureCase: CustomTestStringConvertible {
    enum ToolSet {
      case memory
      case nonMemory
    }

    let tools: ToolSet
    let modelWillExecuteTools: Bool
    let expectsProactiveMemory: Bool
    let expectsProactiveProviderRequest: Bool

    var testDescription: String {
      let toolDescription =
        switch tools {
        case .memory: "memory tools"
        case .nonMemory: "non-memory tools"
        }
      return "\(toolDescription), tool execution: \(modelWillExecuteTools)"
    }
  }

  struct RecentConversationCase: CustomTestStringConvertible {
    enum ToolSet {
      case memory
      case nonMemory
    }

    let tools: ToolSet
    let modelWillExecuteTools: Bool

    var testDescription: String {
      let toolDescription =
        switch tools {
        case .memory: "memory tools"
        case .nonMemory: "non-memory tools"
        }
      return "\(toolDescription), tool execution: \(modelWillExecuteTools)"
    }
  }

  @Test
  func `cross conversation context is suppressed when proactive memory is off`() async {
    let recorder = PromptContextProviderRecorder()
    let messages = await buildMessages(
      input: .init(
        userText: "continue",
        modelName: "test-model",
        modelWillExecuteTools: true,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .off,
        enabledTools: [MTRecallMemoryTool()],
        recorder: recorder,
        proactiveMemoryContext: "Proactive Memory Context\n1. user preference",
        recentConversationContext:
          "Recent conversation context (for background awareness only):\n1. previous chat",
      ),
    )

    let promptTexts = promptTexts(in: messages)
    let recorderSnapshot = await recorder.snapshot()

    #expect(promptTexts.allSatisfy { !$0.contains("Proactive Memory Context") })
    #expect(
      promptTexts.allSatisfy {
        !$0.contains("Recent conversation context (for background awareness only):")
      })
    #expect(recorderSnapshot.proactiveRequests == 0)
    #expect(recorderSnapshot.recentRequests == 0)
    #expect(messages.last?.plainUserText == "continue")
  }

  @Test(arguments: [
    RecentConversationCase(tools: .memory, modelWillExecuteTools: true),
    RecentConversationCase(tools: .memory, modelWillExecuteTools: false),
    RecentConversationCase(tools: .nonMemory, modelWillExecuteTools: true),
    RecentConversationCase(tools: .nonMemory, modelWillExecuteTools: false),
  ])
  func `recent conversation context is injected whenever memory is enabled`(
    _ testCase: RecentConversationCase
  ) async {
    let enabledTools: [any ModelTool] =
      switch testCase.tools {
      case .memory:
        [MTRecallMemoryTool()]
      case .nonMemory:
        [MTWebScraperTool()]
      }
    let recorder = PromptContextProviderRecorder()
    let recentConversationContext =
      "Recent conversation context (for background awareness only):\n1. previous chat"
    let messages = await buildMessages(
      input: .init(
        userText: "continue",
        modelName: "test-model",
        modelWillExecuteTools: testCase.modelWillExecuteTools,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: enabledTools,
        recorder: recorder,
        recentConversationContext: recentConversationContext,
      ),
    )

    let recorderSnapshot = await recorder.snapshot()

    #expect(contextText(in: messages)?.contains(recentConversationContext) == true)
    #expect(recorderSnapshot.recentRequests == 1)
  }

  @Test(arguments: [
    MemoryExposureCase(
      tools: .memory,
      modelWillExecuteTools: true,
      expectsProactiveMemory: true,
      expectsProactiveProviderRequest: true,
    ),
    MemoryExposureCase(
      tools: .memory,
      modelWillExecuteTools: false,
      expectsProactiveMemory: false,
      expectsProactiveProviderRequest: false,
    ),
    MemoryExposureCase(
      tools: .nonMemory,
      modelWillExecuteTools: true,
      expectsProactiveMemory: false,
      expectsProactiveProviderRequest: false,
    ),
    MemoryExposureCase(
      tools: .nonMemory,
      modelWillExecuteTools: false,
      expectsProactiveMemory: false,
      expectsProactiveProviderRequest: false,
    ),
  ])
  func `proactive memory exposure requires both tool execution and a memory tool`(
    _ testCase: MemoryExposureCase
  ) async {
    let enabledTools: [any ModelTool] =
      switch testCase.tools {
      case .memory:
        [MTRecallMemoryTool()]
      case .nonMemory:
        [MTWebScraperTool()]
      }
    let recorder = PromptContextProviderRecorder()

    let messages = await buildMessages(
      input: .init(
        userText: "continue",
        modelName: "test-model",
        modelWillExecuteTools: testCase.modelWillExecuteTools,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: enabledTools,
        recorder: recorder,
        proactiveMemoryContext: "Proactive Memory Context\n1. user preference",
      ),
    )

    let hasProactiveMemory = promptTexts(in: messages).contains {
      $0.contains("Proactive Memory Context")
    }
    let recorderSnapshot = await recorder.snapshot()

    #expect(hasProactiveMemory == testCase.expectsProactiveMemory)
    #expect(
      recorderSnapshot.proactiveRequests == (testCase.expectsProactiveProviderRequest ? 1 : 0))
  }

  @Test
  func `memory tool guidance remains available when proactive memory is off`() async throws {
    let messages = await buildMessages(
      input: .init(
        userText: "continue",
        modelName: "test-model",
        modelWillExecuteTools: true,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .off,
        enabledTools: [MTRecallMemoryTool()],
        proactiveMemoryContext: "Proactive Memory Context\n1. hidden",
        recentConversationContext:
          "Recent conversation context (for background awareness only):\n1. hidden",
      ),
    )

    let guidance = try #require(lastSystemText(in: messages))

    #expect(guidance.contains("store_memory"))
    #expect(!guidance.contains(ConversationSystemPromptBuilder.proactiveMemoryNote))
    #expect(promptTexts(in: messages).allSatisfy { !$0.contains("Proactive Memory Context") })
    #expect(
      promptTexts(in: messages).allSatisfy {
        !$0.contains("Recent conversation context (for background awareness only):")
      })
  }

  @Test
  func `memory tool guidance is omitted when memory tools are unavailable`() async throws {
    let messages = await buildMessages(
      input: .init(
        userText: "continue",
        modelName: "test-model",
        modelWillExecuteTools: true,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: [MTWebScraperTool()],
      ),
    )

    let guidance = try #require(lastSystemText(in: messages))

    #expect(!guidance.isEmpty)
    #expect(!guidance.contains("store_memory"))
  }

  @Test
  func `tool guidance is omitted when tool execution is disabled`() async {
    let messages = await buildMessages(
      input: .init(
        userText: "continue",
        modelName: "test-model",
        modelWillExecuteTools: false,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: [MTRecallMemoryTool()],
      ),
    )

    let toolsDisabledSystemCount = systemTexts(in: messages).count
    let toolsEnabledMessages = await buildMessages(
      input: .init(
        userText: "continue",
        modelName: "test-model",
        modelWillExecuteTools: true,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: [MTRecallMemoryTool()],
      ),
    )
    let toolsEnabledSystemCount = systemTexts(in: toolsEnabledMessages).count
    #expect(toolsDisabledSystemCount < toolsEnabledSystemCount)
  }

  @Test
  func `web search guidance is appended only when the web search tool is enabled`() async {
    let webSearchMessages = await buildMessages(
      input: .init(
        userText: "search this",
        modelName: "test-model",
        modelWillExecuteTools: false,
        webSearchEnabled: true,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: [],
        searchSensitivity: .proactive,
      ),
    )
    let defaultMessages = await buildMessages(
      input: .init(
        userText: "search this",
        modelName: "test-model",
        modelWillExecuteTools: false,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: [],
        searchSensitivity: .proactive,
      ),
    )

    #expect(
      promptTexts(in: webSearchMessages).contains {
        $0.contains("Web Search Mode:")
      })
    #expect(
      promptTexts(in: defaultMessages).allSatisfy {
        !$0.contains("Web Search Mode:")
      })
  }

  @Test
  func `runtime system info is appended only when enabled`() async {
    let enabledMessages = await buildMessages(
      input: .init(
        userText: "hello",
        modelName: "test-model",
        modelWillExecuteTools: false,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: [],
        runtimeSystemInfoProvider: { modelName in
          "runtime info for \(modelName)"
        },
      ),
    )
    let disabledMessages = await buildMessages(
      input: .init(
        userText: "hello",
        modelName: "test-model",
        modelWillExecuteTools: false,
        webSearchEnabled: false,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: [],
        runtimeSystemInfoProvider: nil,
      ),
    )

    #expect(contextText(in: enabledMessages)?.contains("runtime info for test-model") == true)
    #expect(
      promptTexts(in: disabledMessages).allSatisfy {
        !$0.contains("runtime info for")
      })
    // Nothing variable left: the user message goes out exactly as stored.
    #expect(contextText(in: disabledMessages) == nil)
    #expect(disabledMessages.last?.plainUserText == "hello")
  }

  @Test
  func `fixed parts lead and variable context rides on the final user message`() async throws {
    var messages: [ChatRequestBody.Message] = [
      .system(content: .text("stored prompt")),
      .user(content: .text("earlier question")),
      .assistant(content: .text("earlier answer")),
    ]
    await ConversationSystemPromptBuilder.appendMessages(
      to: &messages,
      input: .init(
        userText: "final user message",
        modelName: "test-model",
        modelWillExecuteTools: true,
        webSearchEnabled: true,
      ),
      dependencies: makeFullDependencies(),
    )

    // Fixed: stored prompt, then tool guidance, both ahead of the history.
    #expect(messages.count == 5)
    #expect(messages[0].systemText == "stored prompt")
    let guidance = try #require(messages[1].systemText)
    #expect(guidance.contains("store_memory"))
    #expect(!guidance.contains(ConversationSystemPromptBuilder.proactiveMemoryNote))
    #expect(messages[2].plainUserText == "earlier question")
    #expect(systemTexts(in: messages).count == 2)

    // Variable: one delimited context block leading the final user message,
    // sent as a single string, then a blank line and the user's text.
    let finalText = try #require(messages.last?.userStringContent)
    #expect(finalText.hasSuffix(ConversationSystemPromptBuilder.contextSectionClosing + "\n\nfinal user message"))
    #expect(messages.last?.plainUserText == "final user message")
    let context = try #require(contextText(in: messages))
    #expect(context.hasPrefix(ConversationSystemPromptBuilder.contextSectionOpening + "\n"))
    #expect(context.hasSuffix("\n" + ConversationSystemPromptBuilder.contextSectionClosing))
    let runtime = try #require(context.range(of: "runtime info for test-model"))
    let memory = try #require(context.range(of: "Proactive Memory Context"))
    let note = try #require(context.range(of: ConversationSystemPromptBuilder.proactiveMemoryNote))
    let recent = try #require(context.range(of: "Recent conversation context"))
    let search = try #require(context.range(of: "Web Search Mode:"))
    #expect(runtime.lowerBound < memory.lowerBound)
    #expect(memory.lowerBound < note.lowerBound)
    #expect(note.lowerBound < recent.lowerBound)
    #expect(recent.lowerBound < search.lowerBound)
  }

  @Test
  func `apple intelligence placement keeps the context in its instructions`() async throws {
    var messages: [ChatRequestBody.Message] = [.system(content: .text("stored prompt"))]
    await ConversationSystemPromptBuilder.appendMessages(
      to: &messages,
      input: .init(
        userText: "final user message",
        modelName: "test-model",
        modelWillExecuteTools: true,
        webSearchEnabled: true,
        contextPlacement: .systemMessages,
      ),
      dependencies: makeFullDependencies(),
    )

    let systemTexts = systemTexts(in: messages)
    #expect(systemTexts.count == 6)
    #expect(systemTexts[0] == "stored prompt")
    #expect(systemTexts[1].contains("store_memory"))
    #expect(systemTexts[2] == "runtime info for test-model")
    #expect(systemTexts[3].hasPrefix("Proactive Memory Context"))
    #expect(systemTexts[3].hasSuffix(ConversationSystemPromptBuilder.proactiveMemoryNote))
    #expect(systemTexts[4].contains("Recent conversation context"))
    #expect(systemTexts[5].contains("Web Search Mode:"))
    #expect(messages.last?.plainUserText == "final user message")

    let instructions = AppleIntelligencePromptBuilder.makeInstructions(
      persona: "",
      messages: messages,
      additionalDirectives: [],
    )
    #expect(instructions.contains("runtime info for test-model"))
    #expect(instructions.contains("Proactive Memory Context"))
    #expect(instructions.contains("Web Search Mode:"))
    #expect(AppleIntelligencePromptBuilder.makePrompt(from: messages) == "User: final user message")
  }

  @Test
  func `only apple intelligence takes the context as system messages`() {
    #expect(ConversationSystemPromptBuilder.contextPlacement(for: "cloud-model") == .finalUserMessage)
    if #available(iOS 26.0, macCatalyst 26.0, *) {
      #expect(
        ConversationSystemPromptBuilder.contextPlacement(
          for: AppleIntelligenceModel.shared.modelIdentifier) == .systemMessages)
    }
  }

  @Test
  func `runtime date has day precision with the time zone`() throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let morning = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 0, minute: 5)))
    let night = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 23, minute: 55)))

    #expect(morning.promptDay(in: timeZone) == "2026-11-11 Wednesday (Asia/Shanghai, GMT+08:00)")
    #expect(night.promptDay(in: timeZone) == morning.promptDay(in: timeZone))

    let info = ConversationSystemPromptBuilder.runtimeSystemInfo(
      modelName: "test-model",
      date: morning.promptDay(in: timeZone),
    )
    #expect(info.contains("test-model"))
    #expect(info.contains("2026-11-11 Wednesday (Asia/Shanghai, GMT+08:00)"))
    #expect(!info.contains("00:05"))
  }

  @Test
  func `live dependencies follow the runtime system prompt setting`() async throws {
    try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
    let manager = ModelManager.shared
    let original = manager.includeDynamicSystemInfo
    defer { manager.includeDynamicSystemInfo = original }

    manager.includeDynamicSystemInfo = false
    #expect(ConversationSystemPromptBuilder.Dependencies.live().runtimeSystemInfoProvider == nil)

    manager.includeDynamicSystemInfo = true
    let provider = try #require(
      ConversationSystemPromptBuilder.Dependencies.live().runtimeSystemInfoProvider)
    let info = provider("test-model")
    #expect(info.contains("test-model"))
    #expect(info.contains(Date().promptDay()))
  }

  private func buildMessages(
    input: ConversationSystemPromptBuilder.Input,
    dependencies: ConversationSystemPromptBuilder.Dependencies,
  ) async -> [ChatRequestBody.Message] {
    var messages: [ChatRequestBody.Message] = []
    await ConversationSystemPromptBuilder.appendMessages(
      to: &messages,
      input: input,
      dependencies: dependencies,
    )
    return messages
  }

  private func makeDependencies(
    proactiveMemoryScope: MemoryProactiveProvisionScope,
    enabledTools: [any ModelTool],
    searchSensitivity: ModelManager.SearchSensitivity = .balanced,
    runtimeSystemInfoProvider: ((String) -> String)? = nil,
    recorder: PromptContextProviderRecorder? = nil,
    proactiveMemoryContext: String? = nil,
    recentConversationContext: String? = nil,
  ) -> ConversationSystemPromptBuilder.Dependencies {
    .init(
      enabledTools: enabledTools,
      proactiveMemoryScope: proactiveMemoryScope,
      searchSensitivity: searchSensitivity,
      runtimeSystemInfoProvider: runtimeSystemInfoProvider,
      proactiveMemoryContextProvider: {
        await recorder?.recordProactiveRequest()
        return proactiveMemoryContext
      },
      recentConversationContextProvider: { _ in
        await recorder?.recordRecentRequest()
        return recentConversationContext
      },
    )
  }

  private func makeFullDependencies() -> ConversationSystemPromptBuilder.Dependencies {
    makeDependencies(
      proactiveMemoryScope: .recent30,
      enabledTools: [MTRecallMemoryTool()],
      runtimeSystemInfoProvider: { modelName in
        "runtime info for \(modelName)"
      },
      proactiveMemoryContext: "Proactive Memory Context\n1. user preference",
      recentConversationContext:
        "Recent conversation context (for background awareness only):\n1. previous chat",
    )
  }

  private func systemTexts(in messages: [ChatRequestBody.Message]) -> [String] {
    messages.compactMap(\.systemText)
  }

  /// The context block leading the final user message, nil when it has none.
  private func contextText(in messages: [ChatRequestBody.Message]) -> String? {
    messages.last?.userTextSplit.context
  }

  /// Everything the builder adds as prompt text: system messages and the
  /// final user message's context part.
  private func promptTexts(in messages: [ChatRequestBody.Message]) -> [String] {
    systemTexts(in: messages) + [contextText(in: messages)].compactMap { $0 }
  }

  private func lastSystemText(in messages: [ChatRequestBody.Message]) -> String? {
    systemTexts(in: messages).last
  }
}

private actor PromptContextProviderRecorder {
  struct Snapshot {
    let proactiveRequests: Int
    let recentRequests: Int
  }

  private var proactiveRequests = 0
  private var recentRequests = 0

  func recordProactiveRequest() {
    proactiveRequests += 1
  }

  func recordRecentRequest() {
    recentRequests += 1
  }

  func snapshot() -> Snapshot {
    .init(
      proactiveRequests: proactiveRequests,
      recentRequests: recentRequests,
    )
  }
}

extension ChatRequestBody.Message {
  fileprivate var systemText: String? {
    switch self {
    case .system(let content, _):
      if case .text(let text) = content {
        return text
      }
      return nil
    default:
      return nil
    }
  }

  /// The text the user typed, without any leading context block.
  fileprivate var plainUserText: String? {
    userTextSplit.text
  }

  /// The whole content of a user message sent as a single string.
  fileprivate var userStringContent: String? {
    if case .user(.text(let text), _) = self { return text }
    return nil
  }

  /// A user string split into its leading `<context>` block and the text
  /// after the blank line that follows it.
  fileprivate var userTextSplit: (context: String?, text: String?) {
    guard let text = userStringContent else { return (nil, nil) }
    let opening = ConversationSystemPromptBuilder.contextSectionOpening
    let closing = ConversationSystemPromptBuilder.contextSectionClosing + "\n\n"
    guard text.hasPrefix(opening), let end = text.range(of: closing) else { return (nil, text) }
    return (
      String(text[..<end.lowerBound]) + ConversationSystemPromptBuilder.contextSectionClosing,
      String(text[end.upperBound...])
    )
  }
}
