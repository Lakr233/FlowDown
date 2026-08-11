//
//  RichEditorView+Delegate.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import UIKit

extension RichEditorView {
    protocol Delegate: AnyObject {
        func onRichEditorSubmit(object: Object, completion: @escaping (Bool) -> Void)
        func onRichEditorError(_ error: String)
        func onRichEditorTogglesUpdate(object: Object)
        func onRichEditorRequestObjectForRestore() -> Object?
        func onRichEditorUpdateObject(object: Object)
        func onRichEditorRequestAutomaticModelSelection()
        func onRichEditorRequestCurrentModelName() -> String?
        func onRichEditorRequestCurrentModelIdentifier() -> String?
        func onRichEditorBuildModelSelectionMenu(completion: @escaping () -> Void) -> [UIMenuElement]
        func onRichEditorBuildAlternativeModelMenu() -> [UIMenuElement]
        func onRichEditorCheckIfModelSupportsToolCall(_ modelIdentifier: String) -> Bool
        func onRichEditorBuildAlternativeToolsMenu(isEnabled: Bool, requestReload: @escaping (Bool) -> Void) -> [UIMenuElement]
    }
}
