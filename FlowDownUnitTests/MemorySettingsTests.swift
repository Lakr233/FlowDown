//
//  MemorySettingsTests.swift
//  FlowDownUnitTests
//
//  Created by GPT-5 Codex on 4/11/26.
//

import Testing

@testable import FlowDown

@Suite(.serialized)
struct MemorySettingsTests {
  @MainActor
  @Test
  func `memory context is hidden when request tools are disabled`() {
    let memoryTools: [ModelTool] = [MTRecallMemoryTool()]

    #expect(
      !ModelToolsManager.shouldExposeMemory(
        modelWillExecuteTools: false,
        enabledTools: memoryTools,
      ))
  }

  @MainActor
  @Test
  func `memory context is available only with enabled memory tools`() {
    let nonMemoryTools: [ModelTool] = [MTWebScraperTool()]
    let memoryTools: [ModelTool] = [MTRecallMemoryTool()]

    #expect(
      !ModelToolsManager.shouldExposeMemory(
        modelWillExecuteTools: true,
        enabledTools: nonMemoryTools,
      ))
    #expect(
      ModelToolsManager.shouldExposeMemory(
        modelWillExecuteTools: true,
        enabledTools: memoryTools,
      ))
  }

  @MainActor
  @Test
  func `proactive memory off produces no context`() async {
    let context = await MemoryStore.shared.formattedProactiveMemoryContext(for: .off)

    #expect(context == nil)
  }

  @Test
  func `recent conversation context is disabled when proactive memory is off`() {
    #expect(!MemoryProactiveProvisionSetting.shouldInjectRecentConversationContext(for: .off))
    #expect(MemoryProactiveProvisionSetting.shouldInjectRecentConversationContext(for: .recent15))
    #expect(MemoryProactiveProvisionSetting.shouldInjectRecentConversationContext(for: .recent30))
  }
}
