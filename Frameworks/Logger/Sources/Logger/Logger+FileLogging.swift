import Foundation
import OSLog

enum LogCategoryResolver {
    static func resolve(fileID: String) -> String {
        let lowercased = fileID.lowercased()
        if lowercased.contains("model") { return "Model" }
        if lowercased.contains("network") { return "Network" }
        if lowercased.contains("ui") || lowercased.contains("view") || lowercased.contains("controller") { return "UI" }
        if lowercased.contains("storage") || lowercased.contains("database") { return "Database" }
        return "App"
    }
}

public extension Logger {
    func debugFile(_ message: String, fileID: String = #fileID) {
        logToFile(.debug, message, fileID: fileID)
    }

    func infoFile(_ message: String, fileID: String = #fileID) {
        logToFile(.info, message, fileID: fileID)
    }

    func errorFile(_ message: String, fileID: String = #fileID) {
        logToFile(.error, message, fileID: fileID)
    }

    private func logToFile(_ level: LogLevel, _ message: String, fileID: String) {
        log(level: level.osLogType, "\(message)")
        let resolvedCategory = LogCategoryResolver.resolve(fileID: fileID)
        LogStore.shared.append(level: level, category: resolvedCategory, message: message)
    }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .error: .error
        }
    }
}
