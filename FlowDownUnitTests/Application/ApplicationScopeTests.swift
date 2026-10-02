@testable import FlowDown
import MarkdownView
import Testing
import UIKit

struct ApplicationScopeTests {
    @Test
    func `memory scope filters and privacy gate match the configured scope`() {
        expectFilter(MemoryProactiveProvisionScope.off.filter, equals: .none)
        expectFilter(MemoryProactiveProvisionScope.pastDay.filter, equals: .timeInterval(24 * 60 * 60))
        expectFilter(MemoryProactiveProvisionScope.pastWeek.filter, equals: .timeInterval(7 * 24 * 60 * 60))
        expectFilter(MemoryProactiveProvisionScope.pastMonth.filter, equals: .timeInterval(30 * 24 * 60 * 60))
        expectFilter(MemoryProactiveProvisionScope.pastYear.filter, equals: .timeInterval(365 * 24 * 60 * 60))
        expectFilter(MemoryProactiveProvisionScope.recent15.filter, equals: .count(15))
        expectFilter(MemoryProactiveProvisionScope.recent30.filter, equals: .count(30))
        expectFilter(MemoryProactiveProvisionScope.all.filter, equals: .all)

        #expect(!MemoryProactiveProvisionSetting.shouldInjectRecentConversationContext(for: .off))
        #expect(MemoryProactiveProvisionSetting.shouldInjectRecentConversationContext(for: .recent15))
        #expect(MemoryProactiveProvisionSetting.shouldInjectRecentConversationContext(for: .all))
    }

    @Test
    func `application settings expose stable titles icons and option ordering`() throws {
        #expect(StreamAudioEffectSetting.off.icon == "speaker.slash")
        #expect(StreamAudioEffectSetting.random.icon == "shuffle")
        #expect(StreamAudioEffectSetting.custom.icon == "music.note")
        #expect(StreamAudioEffectSetting.off.audioIndex == nil)
        #expect(StreamAudioEffectSetting.custom.audioIndex == nil)
        #expect(try (0 ... 9).contains(#require(StreamAudioEffectSetting.random.audioIndex)))

        #expect(UIUserInterfaceStyle.cases == [.light, .dark, .unspecified])
        #expect(UIUserInterfaceStyle.light.icon == "sun.max")
        #expect(UIUserInterfaceStyle.dark.icon == "moon")
        #expect(!String(localized: UIUserInterfaceStyle.unspecified.title).isEmpty)

        #expect(!String(localized: MarkdownTheme.FontScale.tiny.title).isEmpty)
        #expect(!String(localized: MarkdownTheme.FontScale.middle.title).isEmpty)
        #expect(!String(localized: MarkdownTheme.FontScale.huge.title).isEmpty)
    }

    private func expectFilter(
        _ actual: MemoryProactiveProvisionScope.Filter,
        equals expected: MemoryProactiveProvisionScope.Filter,
    ) {
        switch (actual, expected) {
        case (.none, .none), (.all, .all):
            #expect(Bool(true))
        case let (.count(lhs), .count(rhs)):
            #expect(lhs == rhs)
        case let (.timeInterval(lhs), .timeInterval(rhs)):
            #expect(lhs == rhs)
        default:
            Issue.record("Unexpected filter combination: \(actual) vs \(expected)")
        }
    }
}
