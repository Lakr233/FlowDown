@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

struct ModelToolsScopeTests {
    @Test
    func `attachment data parser decodes base64 data urls and plaintext fallbacks`() throws {
        let text = "FlowDown"
        let inlineText = "hello world!"
        let base64 = Data(text.utf8).base64EncodedString()

        let directBase64 = try #require(AttachmentDataParser.decodeData(from: base64))
        let dataURL = try #require(AttachmentDataParser.decodeData(from: "data:text/plain;base64,\(base64)"))
        let inlineDataURL = try #require(AttachmentDataParser.decodeData(from: "data:text/plain,\(inlineText)"))
        let fallbackPlaintext = try #require(AttachmentDataParser.decodeData(from: "not-base64"))

        #expect(String(data: directBase64, encoding: .utf8) == text)
        #expect(String(data: dataURL, encoding: .utf8) == text)
        #expect(String(data: inlineDataURL, encoding: .utf8) == inlineText)
        #expect(String(data: fallbackPlaintext, encoding: .utf8) == "not-base64")
        #expect(AttachmentDataParser.decodeData(from: "data:") == nil)
    }

    @Test
    func `web scraper tool repairs empty arguments into object payload`() {
        let repaired = ToolCallArgumentRepair.normalize(
            request: ToolRequest(
                id: "tool-1",
                name: "scrape_web_page",
                args: ""
            ),
            using: [MTWebScraperTool().definition]
        )

        #expect(repaired.args == #"{"url":""}"#)
    }

    @Test
    func `web search tool repairs empty arguments into object payload`() {
        let repaired = ToolCallArgumentRepair.normalize(
            request: ToolRequest(
                id: "tool-2",
                name: "web_search",
                args: ""
            ),
            using: [MTWebSearchTool().definition]
        )

        #expect(repaired.args == #"{"query":""}"#)
    }
}
