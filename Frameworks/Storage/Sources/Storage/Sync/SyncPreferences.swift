//
//  SyncPreferences.swift
//  Storage
//
//  Created by AI on 2025/10/22.
//

import Foundation

/// User preferences controlling iCloud sync behavior and table groups.
public enum SyncPreferences {
    // MARK: - Keys

    private static let manualSyncKey = "com.flowdown.storage.sync.manual.enabled"

    private static let groupConversationsKey = "com.flowdown.storage.sync.group.conversations"
    private static let groupMemoryKey = "com.flowdown.storage.sync.group.memory"
    private static let groupMCPKey = "com.flowdown.storage.sync.group.mcp"
    private static let groupModelsKey = "com.flowdown.storage.sync.group.models"
    private static let groupTemplatesKey = "com.flowdown.storage.sync.group.templates"

    // MARK: - Manual Mode

    public static var isManualSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: manualSyncKey) }
        set { UserDefaults.standard.set(newValue, forKey: manualSyncKey) }
    }

    // MARK: - Group Toggles

    public enum Group: Sendable {
        case conversations // Conversation, Message, Attachment, ConversationSummary
        case memory // Memory
        case mcp // ModelContextServer
        case models // CloudModel
        case templates // ChatTemplateRecord
    }

    private static func key(for group: Group) -> String {
        switch group {
        case .conversations: groupConversationsKey
        case .memory: groupMemoryKey
        case .mcp: groupMCPKey
        case .models: groupModelsKey
        case .templates: groupTemplatesKey
        }
    }

    public static func isGroupEnabled(_ group: Group) -> Bool {
        UserDefaults.standard.object(forKey: key(for: group)) as? Bool ?? true
    }

    public static func setGroup(_ group: Group, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key(for: group))
    }

    /// Map a table name to the preference group.
    public static func group(forTableName table: String) -> Group? {
        switch table {
        case Conversation.tableName, Message.tableName, Attachment.tableName, ConversationSummary.tableName:
            .conversations
        case Memory.tableName:
            .memory
        case ModelContextServer.tableName:
            .mcp
        case CloudModel.tableName:
            .models
        case ChatTemplateRecord.tableName:
            .templates
        default:
            nil
        }
    }

    /// Whether the specified table name is allowed to sync according to preferences.
    public static func isTableSyncEnabled(tableName: String) -> Bool {
        guard let group = group(forTableName: tableName) else { return true }
        return isGroupEnabled(group)
    }

    /// 获取当前启用同步的表
    /// - Returns: 表名集合
    package static func enabledTables() -> [String] {
        [
            Conversation.tableName,
            Message.tableName,
            Attachment.tableName,
            ConversationSummary.tableName,
            CloudModel.tableName,
            Memory.tableName,
            ModelContextServer.tableName,
            ChatTemplateRecord.tableName,
        ].filter { isTableSyncEnabled(tableName: $0) }
    }
}
