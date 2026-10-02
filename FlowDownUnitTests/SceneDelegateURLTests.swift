//
//  SceneDelegateURLTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import Testing

struct SceneDelegateURLTests {
    @Test
    @MainActor
    func newConversationURL_roundTripsThroughSceneParser() throws {
        for text in ["What is 50% of 80?", "Encode A as %41", "A/B testing", "100%", "Hello"] {
            let url = try ShortcutUtilities.newConversationURL(initialMessage: text)
            #expect(SceneDelegate.newConversationMessage(from: url) == text)
        }
    }

    @Test
    @MainActor
    func newConversationURL_withoutMessage_parsesAsEmpty() throws {
        let url = try ShortcutUtilities.newConversationURL(initialMessage: nil)
        #expect(SceneDelegate.newConversationMessage(from: url) == "")
    }

    @Test
    @MainActor
    func newConversationMessage_unencodedSlash_keepsWholeMessage() throws {
        let url = try #require(URL(string: "flowdown://new/A/B%20c"))
        #expect(SceneDelegate.newConversationMessage(from: url) == "A/B c")
    }

    @Test
    @MainActor
    func newConversationMessage_withoutPath_returnsNil() throws {
        let url = try #require(URL(string: "flowdown://new"))
        #expect(SceneDelegate.newConversationMessage(from: url) == nil)
    }
}
