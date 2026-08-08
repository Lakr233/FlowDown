//
//  RichEditorView+Object.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

extension RichEditorView {
    struct Object: Codable {
        var text: String
        var attachments: [Attachment]
        var options: [OptionKey: OptionValue]

        init(text: String = "", attachments: [Attachment] = [], options: [OptionKey: OptionValue] = [:]) {
            self.text = text
            self.attachments = attachments
            self.options = options
        }
    }
}

extension RichEditorView.Object {
    struct Attachment: Codable, Identifiable, Hashable {
        let id: UUID
        let type: AttachmentType
        var name: String
        var previewImage: Data
        var imageRepresentation: Data
        var textRepresentation: String
        var storageSuffix: String

        init(
            id: UUID = .init(),
            type: AttachmentType,
            name: String,
            previewImage: Data,
            imageRepresentation: Data,
            textRepresentation: String,
            storageSuffix: String,
        ) {
            self.id = id
            self.type = type
            self.name = name
            self.previewImage = previewImage
            self.imageRepresentation = imageRepresentation
            self.storageSuffix = storageSuffix
            self.textRepresentation = textRepresentation
        }
    }

    enum OptionKey: String, Codable {
        case tools
        case storagePrefix
        case modelIdentifier
    }

    enum OptionValue: Codable {
        case string(String)
        case bool(Bool)
        case url(URL)
    }
}

extension RichEditorView.Object.Attachment {
    enum AttachmentType: String, Codable {
        case image
        case text
        case audio
    }
}

extension RichEditorView.Object {
    var hasEmptyContent: Bool {
        // text.isEmpty && attachments.isEmpty
        // 要求用户必须发送内容
        text.isEmpty
    }
}

extension RichEditorView {
    func resetValues() {
        inputEditor.set(text: "")
        #if !targetEnvironment(macCatalyst)
            inputEditor.endEditing(true)
        #endif
        attachmentsBar.attachmetns.removeAll()
        controlPanel.close()
        inputEditor.isControlPanelOpened = false
        setNeedsLayout()
        publishNewEditorStatus()
    }

    func submitValues() {
        let object = collectObject()
        guard !object.hasEmptyContent else { return }
        endEditing(true)
        isUserInteractionEnabled = false
        let completion: (Bool) -> Void = { success in
            Task { @MainActor in
                self.isUserInteractionEnabled = true
                if success {
                    self.resetValues()
                    self.storage.removeAll()
                }
            }
        }
        delegate?.onRichEditorSubmit(object: object, completion: completion)
    }

    func publishNewEditorStatus() {
        assert(Thread.isMainThread)
        let object = collectObject()
        guard !objectTransactionInProgress else { return }
        objectTransactionInProgress = true
        defer { objectTransactionInProgress = false }
        delegate?.onRichEditorUpdateObject(object: object)
    }

    func restoreEditorStatusIfPossible() {
        assert(Thread.isMainThread)
        guard let object = delegate?.onRichEditorRequestObjectForRestore() else { return }
        objectTransactionInProgress = true
        defer { objectTransactionInProgress = false }
        resetValues()
        inputEditor.set(text: object.text.trimmingCharacters(in: .whitespacesAndNewlines))
        attachmentsBar.attachmetns.removeAll()
        for attachment in object.attachments {
            attachmentsBar.insert(item: attachment)
        }
        if let tools = object.options[.tools], case let .bool(value) = tools {
            quickSettingBar.toolsToggle.isOn = value
        }
    }

    public func refill(withText text: String, attachments: [Object.Attachment]) {
        inputEditor.set(text: text)
        attachmentsBar.attachmetns.removeAll()
        for attachment in attachments {
            attachmentsBar.insert(item: attachment)
        }
    }
}
