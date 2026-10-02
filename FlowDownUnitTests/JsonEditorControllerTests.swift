@testable import FlowDown
import Foundation
import Testing

@MainActor
struct JsonEditorControllerTests {
    @Test
    func jsonEditorUpdate_invalidJson_throwsWithoutApplyingPreset() {
        var didApplyPreset = false

        do {
            let result = try JsonEditorController.applying({
                didApplyPreset = true
                $0["temperature"] = 0.7
            }, to: "{\"provider\": {\"order\": [\"a\"]}, \"top_p\": 0.9,")
            Issue.record("Expected invalid JSON to throw, got \(result).")
        } catch {}

        #expect(!didApplyPreset)
    }

    @Test
    func jsonEditorUpdate_nonObjectRoot_throws() {
        do {
            let result = try JsonEditorController.applying({ $0["temperature"] = 0.7 }, to: "[1]")
            Issue.record("Expected a non-object root to throw, got \(result).")
        } catch {
            #expect((error as NSError).domain == "JSONValidation")
        }
    }

    @Test
    func jsonEditorUpdate_validJson_mergesKey() throws {
        let result = try JsonEditorController.applying({ $0["temperature"] = 0.7 }, to: "{\"a\":1}")

        #expect(result["a"] as? Int == 1)
        #expect(result["temperature"] as? Double == 0.7)
    }

    @Test
    func jsonEditorUpdate_emptyText_startsFromEmptyObject() throws {
        let result = try JsonEditorController.applying({ $0["temperature"] = 0.7 }, to: "  \n")

        #expect(result.count == 1)
        #expect(result["temperature"] as? Double == 0.7)
    }
}
