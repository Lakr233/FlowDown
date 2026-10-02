@testable import FlowDown
import Foundation
import Testing

@MainActor
struct CloudModelEditorBodyFieldsTests {
    @Test
    func addProviderOrder_existingProvider_nestsOrderUnderProvider() throws {
        var dictionary: [String: Any] = ["provider": ["zdr": true]]

        CloudModelEditorController.addProviderOrder(to: &dictionary)

        #expect(dictionary["order"] == nil)
        let provider = try #require(dictionary["provider"] as? [String: Any])
        #expect((provider["order"] as? [String]) == [])
        #expect((provider["zdr"] as? Bool) == true)
    }

    @Test
    func addProviderOrder_noProvider_createsProviderWithOrder() throws {
        var dictionary: [String: Any] = ["temperature": 0.7]

        CloudModelEditorController.addProviderOrder(to: &dictionary)

        #expect(dictionary["order"] == nil)
        #expect((dictionary["temperature"] as? Double) == 0.7)
        let provider = try #require(dictionary["provider"] as? [String: Any])
        #expect((provider["order"] as? [String]) == [])
    }

    @Test
    func addProviderOrder_existingOrder_keepsOrder() throws {
        var dictionary: [String: Any] = ["provider": ["order": ["openai", "anthropic"]]]

        CloudModelEditorController.addProviderOrder(to: &dictionary)

        let provider = try #require(dictionary["provider"] as? [String: Any])
        #expect((provider["order"] as? [String]) == ["openai", "anthropic"])
    }
}
