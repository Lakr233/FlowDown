@testable import FlowDown
import Foundation
import Testing
import UIKit

/// Stands in for ChatView: keeps the last published draft and hands it back on
/// restore, the way ConversationManager does for a conversation.
@MainActor
private final class RichEditorDelegateSpy: RichEditorView.Delegate {
    var storedObject: RichEditorView.Object?
    var modelIdentifier: String?
    var supportsToolCall = false
    private(set) var updatedObjects: [RichEditorView.Object] = []
    private(set) var submittedObjects: [RichEditorView.Object] = []
    private(set) var errors: [String] = []

    func onRichEditorSubmit(object: RichEditorView.Object, completion _: @escaping (Bool) -> Void) {
        submittedObjects.append(object)
    }

    func onRichEditorError(_ error: String) {
        errors.append(error)
    }

    func onRichEditorTogglesUpdate(object _: RichEditorView.Object) {}

    func onRichEditorRequestObjectForRestore() -> RichEditorView.Object? {
        storedObject
    }

    func onRichEditorUpdateObject(object: RichEditorView.Object) {
        updatedObjects.append(object)
        storedObject = object
    }

    func onRichEditorRequestAutomaticModelSelection() {}

    func onRichEditorRequestCurrentModelName() -> String? {
        modelIdentifier
    }

    func onRichEditorRequestCurrentModelIdentifier() -> String? {
        modelIdentifier
    }

    func onRichEditorBuildModelSelectionMenu(completion _: @escaping () -> Void) -> [UIMenuElement] {
        []
    }

    func onRichEditorBuildAlternativeModelMenu() -> [UIMenuElement] {
        []
    }

    func onRichEditorCheckIfModelSupportsToolCall(_: String) -> Bool {
        supportsToolCall
    }

    func onRichEditorBuildAlternativeToolsMenu(
        isEnabled _: Bool,
        requestReload _: @escaping (Bool) -> Void,
    ) -> [UIMenuElement] {
        []
    }
}

@Suite(.serialized)
struct RichEditorViewTests {
    @MainActor
    @Test
    func richEditorUse_toolAvailabilityChange_preservesDraft() {
        let toolsKey = QuickSettingBar.toolsEnabledKey
        let previousToolsValue = UserDefaults.standard.object(forKey: toolsKey)
        defer { UserDefaults.standard.set(previousToolsValue, forKey: toolsKey) }
        QuickSettingBar.toolsEnabledValue = true

        let spy = RichEditorDelegateSpy()
        spy.storedObject = .init(text: "hello")
        spy.modelIdentifier = "tool-capable-model"
        spy.supportsToolCall = true

        let editor = RichEditorView()
        editor.delegate = spy
        // The previous conversation's model left the tools toggle off, so
        // switching to this one turns it on.
        editor.quickSettingBar.updateToolCallAvailability(false)

        editor.use(identifier: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: editor.storage.storageDir) }

        #expect(editor.quickSettingBar.toolsToggle.isOn)
        #expect(editor.inputEditor.textView.text == "hello")
        #expect(!spy.updatedObjects.contains(where: { $0.text.isEmpty }))
        #expect(spy.storedObject?.text == "hello")
    }

    @MainActor
    @Test
    func richEditorDraft_attachmentOnly_publishesEmptyText() {
        let spy = RichEditorDelegateSpy()
        let editor = RichEditorView()
        editor.delegate = spy

        let attachment = RichEditorView.Object.Attachment(
            type: .text,
            name: "notes.txt",
            previewImage: .init(),
            imageRepresentation: .init(),
            textRepresentation: "notes",
            storageSuffix: UUID().uuidString,
        )
        editor.attachmentsBar.insert(item: attachment)

        let draft = spy.updatedObjects.last
        #expect(draft?.text == "")
        #expect(draft?.attachments.count == 1)

        editor.submitValues()

        #expect(spy.submittedObjects.count == 1)
        #expect(spy.submittedObjects.first?.text == String(localized: "Attached \(1) Documents"))
        #expect(spy.submittedObjects.first?.attachments.count == 1)
    }

    @MainActor
    @Test
    func attachmentFromFile_unsupportedBinary_leavesNoCopy() throws {
        let storage = TemporaryStorage(id: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage.storageDir) }

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bin")
        // Invalid UTF-8 with no byte order mark, so it cannot be read as text.
        try Data([0xC3, 0x28, 0xA0, 0xA1, 0xE2, 0x28, 0xA1, 0xF0, 0x28, 0x8C, 0xBC]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let attachment = RichEditorView.Object.Attachment(file: source, storage: storage)

        #expect(attachment == nil)
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: storage.storageDir,
            includingPropertiesForKeys: nil,
        )
        #expect(leftovers.isEmpty)
    }

    @MainActor
    @Test
    func richEditorProcessFile_oversizedText_leavesNoCopy() throws {
        let spy = RichEditorDelegateSpy()
        let editor = RichEditorView()
        editor.delegate = spy
        editor.storage = TemporaryStorage(id: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: editor.storage.storageDir) }

        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try String(repeating: "a", count: 1_000_001).write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        editor.process(file: source)

        #expect(spy.errors.count == 1)
        #expect(editor.collectObject().attachments.isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: editor.storage.storageDir,
            includingPropertiesForKeys: nil,
        )
        #expect(leftovers.isEmpty)
    }
}
