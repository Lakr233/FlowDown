import Foundation

public final class LogStore: @unchecked Sendable {
    public static let shared = LogStore()

    let queue: DispatchQueue
    let fileManager: FileManager
    let maxFileSize: Int
    let maxFiles: Int
    let logDirectory: URL
    let logFileName: String

    private lazy var timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        queue: DispatchQueue? = nil,
        maxFileSize: Int = 5 * 1024 * 1024,
        maxFiles: Int = 5,
        fileName: String = "FlowDown.log",
    ) {
        self.fileManager = fileManager
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles
        logFileName = fileName
        self.queue = queue ?? DispatchQueue(label: "wiki.qaq.flowdown.logstore", qos: .utility)

        let base = directory ?? Self.defaultBaseDirectory(fileManager: fileManager)
        let dir = Self.logDirectory(baseDirectory: base)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        logDirectory = dir
    }

    var logFileURL: URL {
        logDirectory.appendingPathComponent(logFileName)
    }

    public func append(level: LogLevel, category: String, message: String) {
        let line = formattedLine(level: level, category: category, message: message)
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try ensureLogFileExists()
                let handle = try FileHandle(forWritingTo: logFileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
                try rotateIfNeeded()
            } catch {
                // Ignore disk write failures to avoid crashing logging callers
            }
        }
    }

    public func readTail(maxBytes: Int = 128 * 1024) -> String {
        queue.sync {
            guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return "" }
            defer { try? handle.close() }

            let fileSize = (try? handle.seekToEnd()) ?? 0
            let startOffset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
            try? handle.seek(toOffset: startOffset)
            let data = (try? handle.readToEnd()) ?? Data()
            // The byte cut can land inside a multi-byte character; skip its continuation bytes.
            let body = startOffset > 0 ? data.drop(while: { $0 & 0xC0 == 0x80 }) : data
            return String(decoding: body, as: UTF8.self)
        }
    }

    public func clear() {
        queue.sync {
            removeCurrentLogs()
        }
    }

    public func flush() {
        queue.sync {}
    }

    public func clearLegacyCacheDirectory() {
        queue.sync {
            guard let legacyDirectory = Self.legacyCacheLogDirectory(fileManager: fileManager) else { return }
            guard legacyDirectory.standardizedFileURL != logDirectory.standardizedFileURL else { return }
            removeLogDirectory(at: legacyDirectory)
        }
    }

    private func formattedLine(level: LogLevel, category: String, message: String) -> Data {
        let timestamp = timestampFormatter.string(from: Date())
        return "\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n".data(using: .utf8) ?? Data()
    }

    private func ensureLogFileExists() throws {
        if !fileManager.fileExists(atPath: logFileURL.path) {
            let dir = logFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            fileManager.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    private func rotateIfNeeded() throws {
        let attributes = try fileManager.attributesOfItem(atPath: logFileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue >= maxFileSize else { return }

        for index in stride(from: maxFiles - 1, through: 1, by: -1) {
            let source = rotatedFileURL(index: index)
            let destination = rotatedFileURL(index: index + 1)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: source, to: destination)
            }
        }

        let first = rotatedFileURL(index: 1)
        if fileManager.fileExists(atPath: first.path) {
            try? fileManager.removeItem(at: first)
        }
        try fileManager.moveItem(at: logFileURL, to: first)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
    }

    func rotatedFileURL(index: Int) -> URL {
        logDirectory.appendingPathComponent("\(logFileName).\(index)")
    }

    private func removeRotatedFiles() {
        for index in 1 ... maxFiles {
            try? fileManager.removeItem(at: rotatedFileURL(index: index))
        }
    }

    func removeCurrentLogs() {
        try? fileManager.removeItem(at: logFileURL)
        removeRotatedFiles()
    }

    func removeLogDirectory(at directory: URL) {
        try? fileManager.removeItem(at: directory)
    }

    static func defaultBaseDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static func legacyCacheLogDirectory(fileManager: FileManager) -> URL? {
        guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return logDirectory(baseDirectory: base)
    }

    static func logDirectory(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent("Logs", isDirectory: true)
    }
}
