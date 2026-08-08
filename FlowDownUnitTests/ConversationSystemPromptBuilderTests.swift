//
//  ConversationSystemPromptBuilderTests.swift
//  FlowDownUnitTests
//
//  Created by GPT-5 Codex on 4/12/26.
//

import ChatClientKit
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

    let systemTexts = systemTexts(in: messages)
    let recorderSnapshot = await recorder.snapshot()

    #expect(systemTexts.allSatisfy { !$0.contains("Proactive Memory Context") })
    #expect(
      systemTexts.allSatisfy {
        !$0.contains("Recent conversation context (for background awareness only):")
      })
    #expect(recorderSnapshot.proactiveRequests == 0)
    #expect(recorderSnapshot.recentRequests == 0)
    #expect(messages.last?.userText == "continue")
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
    let enabledTools: [ModelTool] =
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

    #expect(systemTexts(in: messages).contains(recentConversationContext))
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
    let enabledTools: [ModelTool] =
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

    let hasProactiveMemory = systemTexts(in: messages).contains {
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
    #expect(!guidance.contains("A proactive memory summary has been provided above"))
    #expect(systemTexts(in: messages).allSatisfy { !$0.contains("Proactive Memory Context") })
    #expect(
      systemTexts(in: messages).allSatisfy {
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
        enabledTools: [MTURLTool()],
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
      systemTexts(in: webSearchMessages).contains {
        $0.contains("Web Search Mode:")
      })
    #expect(
      systemTexts(in: defaultMessages).allSatisfy {
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

    #expect(systemTexts(in: enabledMessages).contains("runtime info for test-model"))
    #expect(
      systemTexts(in: disabledMessages).allSatisfy {
        !$0.contains("runtime info for")
      })
  }

  @Test
  func `user text remains the final message after all system context`() async {
    let messages = await buildMessages(
      input: .init(
        userText: "final user message",
        modelName: "test-model",
        modelWillExecuteTools: true,
        webSearchEnabled: true,
      ),
      dependencies: makeDependencies(
        proactiveMemoryScope: .recent30,
        enabledTools: [MTRecallMemoryTool()],
        runtimeSystemInfoProvider: { modelName in
          "runtime info for \(modelName)"
        },
        proactiveMemoryContext: "Proactive Memory Context\n1. user preference",
        recentConversationContext:
          "Recent conversation context (for background awareness only):\n1. previous chat",
      ),
    )

    let systemTexts = systemTexts(in: messages)

    #expect(systemTexts.count == 5)
    #expect(systemTexts[0] == "runtime info for test-model")
    #expect(systemTexts[1].contains("Proactive Memory Context"))
    #expect(systemTexts[2].contains("Recent conversation context (for background awareness only):"))
    #expect(systemTexts[3].contains("Web Search Mode:"))
    #expect(!systemTexts[4].isEmpty)
    #expect(messages.dropLast().allSatisfy { $0.systemText != nil })
    #expect(messages.last?.userText == "final user message")
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
    enabledTools: [ModelTool],
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

  private func systemTexts(in messages: [ChatRequestBody.Message]) -> [String] {
    messages.compactMap(\.systemText)
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

  fileprivate var userText: String? {
    switch self {
    case .user(let content, _):
      if case .text(let text) = content {
        return text
      }
      return nil
    default:
      return nil
    }
  }
}
