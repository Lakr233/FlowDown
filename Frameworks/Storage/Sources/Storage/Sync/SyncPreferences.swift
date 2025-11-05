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
        case conversations // Conversation, Message, Attachment
        case memory // Memory
        case mcp // ModelContextServer
        case models // CloudModel
        case templates // ChatTemplateRecord
    }

    public static func isGroupEnabled(_ group: Group) -> Bool {
        switch group {
        case .conversations:
            UserDefaults.standard.object(forKey: groupConversationsKey) as? Bool ?? true
        case .memory:
            UserDefaults.standard.object(forKey: groupMemoryKey) as? Bool ?? true
        case .mcp:
            UserDefaults.standard.object(forKey: groupMCPKey) as? Bool ?? true
        case .models:
            UserDefaults.standard.object(forKey: groupModelsKey) as? Bool ?? true
        case .templates:
            UserDefaults.standard.object(forKey: groupTemplatesKey) as? Bool ?? true
        }
    }

    public static func setGroup(_ group: Group, enabled: Bool) {
        let key: String = switch group {
        case .conversations: groupConversationsKey
        case .memory: groupMemoryKey
        case .mcp: groupMCPKey
        case .models: groupModelsKey
        case .templates: groupTemplatesKey
        }
        UserDefaults.standard.set(enabled, forKey: key)
    }

    /// Map a table name to the preference group.
    public static func group(forTableName table: String) -> Group? {
        switch table {
        case Conversation.tableName, Message.tableName, Attachment.tableName:
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
        var tables: [String] = []

        if SyncPreferences.isGroupEnabled(.conversations) {
            tables.append(Conversation.tableName)
            tables.append(Message.tableName)
            tables.append(Attachment.tableName)
        }

        if SyncPreferences.isGroupEnabled(.models) {
            tables.append(CloudModel.tableName)
        }

        if SyncPreferences.isGroupEnabled(.memory) {
            tables.append(Memory.tableName)
        }

        if SyncPreferences.isGroupEnabled(.mcp) {
            tables.append(ModelContextServer.tableName)
        }

        if SyncPreferences.isGroupEnabled(.templates) {
            tables.append(ChatTemplateRecord.tableName)
        }

        return tables
    }
}
