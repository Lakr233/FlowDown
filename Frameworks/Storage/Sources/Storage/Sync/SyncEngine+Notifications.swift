//
//  SyncEngine+Notifications.swift
//  Storage
//

import Foundation

extension SyncEngine {
    /// 会话列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ConversationChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ConversationChanged")
    /// 消息列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let MessageChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.MessageChanged")
    /// 模型列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let CloudModelChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.CloudModelChanged")
    /// MCP列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ModelContextServerChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ModelContextServerChanged")
    /// 记忆列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let MemoryChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.MemoryChanged")
    /// 模板列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ChatTemplateChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ChatTemplateChanged")
    /// 会话摘要变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ConversationSummaryChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ConversationSummaryChanged")
    /// 本地数据删除通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let LocalDataDeleted: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.LocalDataDeleted")
    /// 云端数据删除通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ServerDataDeleted: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ServerDataDeleted")
    /// 同步状态通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let SyncStatusChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.SyncStatusChanged")
    public static let ConversationNotificationKey: String = "Conversation"
    public static let MessageNotificationKey: String = "Message"
    public static let CloudModelNotificationKey: String = "CloudModel"
    public static let ModelContextServerNotificationKey: String = "ModelContextServer"
    public static let MemoryNotificationKey: String = "Memory"
    public static let ChatTemplateNotificationKey: String = "ChatTemplate"
    public static let ConversationSummaryNotificationKey: String = "ConversationSummary"
}
