@testable import FlowDown
import Testing

struct ConversationSelectionViewTests {
    @Test
    @MainActor
    func selectionReconcile_removedConversation_fallsBackToFirst() {
        let available: Set<String> = ["a", "b"]
        let replacement = ConversationSelectionView.replacementSelection(
            for: "x",
            displayed: ["a", "b"],
            isAvailable: { available.contains($0) },
        )
        #expect(replacement == "a")
    }

    @Test
    @MainActor
    func selectionReconcile_presentConversation_isKept() {
        let available: Set<String> = ["a", "b"]
        let replacement = ConversationSelectionView.replacementSelection(
            for: "b",
            displayed: ["a", "b"],
            isAvailable: { available.contains($0) },
        )
        #expect(replacement == nil)
    }

    @Test
    @MainActor
    func selectionReconcile_noSelection_isKept() {
        let available: Set<String> = ["a", "b"]
        let replacement = ConversationSelectionView.replacementSelection(
            for: nil,
            displayed: ["a", "b"],
            isAvailable: { available.contains($0) },
        )
        #expect(replacement == nil)
    }

    @Test
    @MainActor
    func selectionReconcile_outdatedRows_isKept() {
        // The rows on display can lag behind the list, for example while the
        // list is empty and a replacement conversation is still being made.
        // Falling back to a row that is gone too would only move the chat to
        // another removed conversation.
        let available: Set<String> = ["c"]
        let replacement = ConversationSelectionView.replacementSelection(
            for: "x",
            displayed: ["a", "b"],
            isAvailable: { available.contains($0) },
        )
        #expect(replacement == nil)
    }
}
