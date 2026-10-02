@testable import FlowDown
import FlowDownModelExchange
import Foundation
import Storage
import Testing
import UIKit

struct InterfaceScopeTests {
    @Test
    func `conversation search result retains matched metadata`() {
        let conversation = Conversation(deviceId: Storage.deviceId)
        conversation.update(\.title, to: "Searchable Conversation")
        let result = ConversationSearchResult(
            conversation: conversation,
            matchType: .message,
            matchedText: "needle",
            messagePreview: "preview text",
        )

        #expect(result.conversation.id == conversation.id)
        switch result.matchType {
        case .message:
            #expect(Bool(true))
        case .title:
            Issue.record("Expected message match type")
        }
        #expect(result.matchedText == "needle")
        #expect(result.messagePreview == "preview text")
    }

    @Test
    func `model exchange capability summaries preserve capability ordering and empty fallback`() {
        let capabilities: [ModelExchangeCapability] = [.visual, .tool, .developerRole]
        let summary = ModelExchangeCapability.summary(from: capabilities)

        let expectedSummary = [
            ModelExchangeCapability.visual,
            ModelExchangeCapability.tool,
            ModelExchangeCapability.developerRole,
        ].map(\.displayName).joined(separator: ", ")
        #expect(summary == expectedSummary)
        #expect(!ModelExchangeCapability.summary(from: []).isEmpty)
    }

    @MainActor
    @Test
    func `text measurement helper reflects width and line limit constraints`() {
        let helper = TextMeasurementHelper()
        let text = NSAttributedString(
            string: String(repeating: "FlowDown measurement ", count: 12),
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
            ],
        )

        let wide = helper.measureSize(of: text, usingWidth: 320)
        let narrow = helper.measureSize(of: text, usingWidth: 120)
        let singleLine = helper.measureSize(of: text, usingWidth: 120, lineLimit: 1)

        #expect(narrow.height >= wide.height)
        #expect(singleLine.height <= narrow.height)
    }

    @Test
    func `welcome experience only presents until the current version is marked seen`() {
        let key = "WelcomeExperience.lastSeenVersion"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        #expect(WelcomeExperience.shouldPresent)
        WelcomeExperience.markPresented()
        #expect(!WelcomeExperience.shouldPresent)
    }
}
