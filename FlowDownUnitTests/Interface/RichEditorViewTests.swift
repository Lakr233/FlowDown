import Combine
@testable import FlowDown
import Foundation
import Storage
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
    /// Models that can read images; every other model is text only.
    var visionModels: Set<String> = []
    static let visualHint = "image cannot be read"

    func onRichEditorSubmit(object: RichEditorView.Object, completion _: @escaping (Bool) -> Void) {
        submittedObjects.append(object)
    }

    func onRichEditorError(_ error: String) {
        errors.append(error)
    }

    func onRichEditorVisualInputHint(
        attachments: [RichEditorView.Object.Attachment],
        modelIdentifier: String,
    ) -> String? {
        guard !modelIdentifier.isEmpty else { return nil }
        let capabilities: Set<ModelCapabilities> = visionModels.contains(modelIdentifier) ? [.visual] : []
        guard ConversationSession.hasImagesRequiringVisualInput(attachments, modelCapabilities: capabilities)
        else { return nil }
        return Self.visualHint
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
    private static func imageAttachment() -> RichEditorView.Object.Attachment {
        .init(
            type: .image,
            name: "square.png",
            previewImage: .init(),
            imageRepresentation: .init(),
            textRepresentation: "",
            storageSuffix: UUID().uuidString,
        )
    }

    @MainActor
    @Test
    func richEditorVisualInputHint_followsAttachmentsAndModel() {
        let spy = RichEditorDelegateSpy()
        spy.modelIdentifier = "text-only"
        spy.visionModels = ["vision"]
        let editor = RichEditorView()
        editor.delegate = spy
        editor.updateModelinfoFile(postUpdate: false)

        let text = RichEditorView.Object.Attachment(
            type: .text,
            name: "notes.txt",
            previewImage: .init(),
            imageRepresentation: .init(),
            textRepresentation: "notes",
            storageSuffix: UUID().uuidString,
        )
        editor.attachmentsBar.insert(item: text)
        #expect(!editor.visualInputHint.isActive)
        #expect(editor.visualInputHint.heightPublisher.value == 0)

        let image = Self.imageAttachment()
        editor.attachmentsBar.insert(item: image)
        #expect(editor.visualInputHint.isActive)
        #expect(editor.visualInputHint.label.text == RichEditorDelegateSpy.visualHint)
        #expect(editor.visualInputHint.heightPublisher.value > 0)

        // Switching to a vision model clears the note, switching back shows it again.
        spy.modelIdentifier = "vision"
        editor.updateModelinfoFile(postUpdate: false)
        #expect(!editor.visualInputHint.isActive)
        spy.modelIdentifier = "text-only"
        editor.updateModelinfoFile(postUpdate: false)
        #expect(editor.visualInputHint.isActive)

        // Removing the image clears it as well.
        editor.attachmentsBar.delete(itemIdentifier: image.id)
        #expect(!editor.visualInputHint.isActive)
        #expect(editor.visualInputHint.heightPublisher.value == 0)
    }

    @MainActor
    @Test
    func richEditorRestore_draftWithImage_showsHintForTextOnlyModel() {
        let spy = RichEditorDelegateSpy()
        spy.modelIdentifier = "text-only"
        spy.storedObject = .init(text: "look", attachments: [Self.imageAttachment()])
        let editor = RichEditorView()
        editor.delegate = spy

        editor.use(identifier: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: editor.storage.storageDir) }

        #expect(editor.collectObject().attachments.count == 1)
        #expect(editor.visualInputHint.isActive)
    }

    @MainActor
    @Test
    func richEditorVisualInputHint_noModelSelected_staysHidden() {
        let spy = RichEditorDelegateSpy()
        let editor = RichEditorView()
        editor.delegate = spy
        editor.updateModelinfoFile(postUpdate: false)

        editor.attachmentsBar.insert(item: Self.imageAttachment())
        #expect(!editor.visualInputHint.isActive)
        #expect(editor.inputEditor.sendButton.isEnabled)
    }

    @MainActor
    @Test
    func richEditorSendButton_followsHint() {
        let spy = RichEditorDelegateSpy()
        spy.modelIdentifier = "text-only"
        spy.visionModels = ["vision"]
        let editor = RichEditorView()
        editor.delegate = spy
        editor.updateModelinfoFile(postUpdate: false)
        let sendButton = editor.inputEditor.sendButton
        #expect(sendButton.isEnabled)
        #expect(sendButton.isAccessibilityElement)
        #expect(sendButton.accessibilityTraits.contains(.button))
        #expect(sendButton.accessibilityLabel == String(localized: "Send"))

        let image = Self.imageAttachment()
        editor.attachmentsBar.insert(item: image)
        #expect(!sendButton.isEnabled)
        #expect(sendButton.accessibilityTraits.contains(.notEnabled))

        spy.modelIdentifier = "vision"
        editor.updateModelinfoFile(postUpdate: false)
        #expect(sendButton.isEnabled)
        #expect(!sendButton.accessibilityTraits.contains(.notEnabled))

        spy.modelIdentifier = "text-only"
        editor.updateModelinfoFile(postUpdate: false)
        #expect(!sendButton.isEnabled)

        editor.attachmentsBar.delete(itemIdentifier: image.id)
        #expect(sendButton.isEnabled)
    }

    @MainActor
    @Test
    func richEditorSubmit_imageForTextOnlyModel_blocksEveryPathAndKeepsDraft() {
        let previousConfirmation = EditorBehavior.useConfirmationOnSend
        defer { EditorBehavior.useConfirmationOnSend = previousConfirmation }
        EditorBehavior.useConfirmationOnSend = false

        let spy = RichEditorDelegateSpy()
        spy.modelIdentifier = "text-only"
        spy.visionModels = ["vision"]
        let editor = RichEditorView()
        editor.delegate = spy
        editor.updateModelinfoFile(postUpdate: false)
        editor.inputEditor.set(text: "look")
        editor.attachmentsBar.insert(item: Self.imageAttachment())

        let input = editor.inputEditor
        editor.submitValues()
        input.sendButton.tapAction()
        input.textView.onReturnKeyPressed()
        input.textView.onCommandReturnKeyPressed()
        _ = input.textView(input.textView, shouldChangeTextIn: NSRange(), replacementText: "\n")

        #expect(spy.submittedObjects.isEmpty)
        #expect(spy.errors.isEmpty)
        #expect(editor.isUserInteractionEnabled)
        #expect(editor.collectObject().text == "look")
        #expect(editor.collectObject().attachments.count == 1)

        spy.modelIdentifier = "vision"
        editor.updateModelinfoFile(postUpdate: false)
        input.textView.onReturnKeyPressed()
        #expect(spy.submittedObjects.count == 1)
        #expect(spy.submittedObjects.first?.attachments.count == 1)
    }

    @MainActor
    @Test
    func richEditorSubmit_rechecksCurrentModel() {
        let spy = RichEditorDelegateSpy()
        spy.modelIdentifier = "vision"
        spy.visionModels = ["vision"]
        let editor = RichEditorView()
        editor.delegate = spy
        editor.updateModelinfoFile(postUpdate: false)
        editor.inputEditor.set(text: "look")
        editor.attachmentsBar.insert(item: Self.imageAttachment())
        #expect(editor.inputEditor.sendButton.isEnabled)

        // The model changes with no refresh reaching the editor.
        spy.modelIdentifier = "text-only"
        editor.submitValues()
        #expect(spy.submittedObjects.isEmpty)
        #expect(editor.visualInputHint.isActive)
        #expect(!editor.inputEditor.sendButton.isEnabled)

        spy.modelIdentifier = "vision"
        editor.submitValues()
        #expect(spy.submittedObjects.count == 1)
        #expect(!editor.visualInputHint.isActive)
        #expect(editor.inputEditor.sendButton.isEnabled)
    }

    @MainActor
    @Test
    func iconButton_disabled_ignoresTaps() {
        let button = IconButton(icon: "send")
        var tapCount = 0
        button.tapAction = { tapCount += 1 }
        let tap = NSSelectorFromString("buttonAction")

        button.isEnabled = false
        button.perform(tap)
        #expect(tapCount == 0)

        button.isEnabled = true
        button.perform(tap)
        #expect(tapCount == 1)
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
