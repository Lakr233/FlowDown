@testable import FlowDown
import Testing

struct ConversationScopeTests {
    @Test
    func `rewrite actions expose non empty prompts titles and icons`() {
        #expect(RewriteAction.allCases.count == 6)

        for action in RewriteAction.allCases {
            #expect(!action.title.isEmpty)
            #expect(!action.prompt.isEmpty)
            #expect(action.icon != nil)
        }
    }

    @Test
    func `conversation metadata tool call decodes title and icon from arguments`() {
        let arguments = #"{"title": "Kyoto trip plan", "icon": "⛩️"}"#

        let metadata = ConversationMetadataToolCall.parse(arguments: arguments)

        #expect(metadata == ConversationMetadata(title: "Kyoto trip plan", icon: "⛩️"))
    }

    @Test
    func `conversation metadata tool call supports partial arguments`() {
        let titleOnly = #"{"title": "Budget review notes"}"#

        let metadata = ConversationMetadataToolCall.parse(arguments: titleOnly)

        #expect(metadata == ConversationMetadata(title: "Budget review notes", icon: nil))
    }

    @Test
    func `conversation metadata tool call rejects malformed arguments`() {
        #expect(ConversationMetadataToolCall.parse(arguments: "not json") == nil)
        #expect(ConversationMetadataToolCall.parse(arguments: #"{"title": "  ", "icon": ""}"#) == nil)
    }

    @Test
    func `conversation metadata tool call preserves title normalization rules`() {
        let normalized = ConversationMetadataToolCall.normalizedTitle(
            "**1234567890123456789012345678901234567890**",
        )

        #expect(normalized == "12345678901234567890123456789012")
    }

    @Test
    func `conversation metadata tool call extracts first emoji from verbose icon value`() {
        let normalized = ConversationMetadataToolCall.normalizedIcon("Status ✅ complete")

        #expect(normalized == "✅")
    }
}
