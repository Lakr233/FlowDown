//
//  ExtensionKey.swift
//  Storage
//
//  Reserved keys used in `ExtensionDictionary` across modules.
//  Any new reserved key **must** be registered here.
//  **永不 rename**:已经写入用户库的 key 名是合约。
//

import Foundation

public enum ExtensionKey {
    /// CloudModel.ext_data 里挂 plist-encoded `ChatClientKitScriptConfig` 的位置。
    public static let chatClientKitScripts = "chat_client_kit_scripts"

    /// Conversation.ext_data 里挂脚本运行时上下文(JSON 字符串,脚本通过 cck.saveContext 写入)。
    public static let chatClientKit = "chat_client_kit"
}
