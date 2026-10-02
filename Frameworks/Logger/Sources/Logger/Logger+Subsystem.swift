@_exported import Foundation
@_exported import OSLog

public extension Logger {
    private static let loggingSubsystem: String = {
        if let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty {
            return identifier
        }
        return ProcessInfo.processInfo.processName
    }()

    static let database = Logger(subsystem: loggingSubsystem, category: "Database")
    static let syncEngine = Logger(subsystem: loggingSubsystem, category: "SyncEngine")
    static let chatService = Logger(subsystem: loggingSubsystem, category: "ChatService")
    static let app = Logger(subsystem: loggingSubsystem, category: "App")
    static let ui = Logger(subsystem: loggingSubsystem, category: "UI")
    static let network = Logger(subsystem: loggingSubsystem, category: "Network")
    static let model = Logger(subsystem: loggingSubsystem, category: "Model")
}
