import Foundation

public final class LogStore: @unchecked Sendable {
    public static let shared = LogStore()

    private let queue = DispatchQueue(label: "wiki.qaq.flowdown.logstore", qos: .utility)
    private let fileManager = FileManager.default
    private let maxFileSize: Int
    private let maxFiles: Int
    let logDirectory: URL
    private let logFileName = "FlowDown.log"

    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(
        directory: URL? = nil,
        maxFileSize: Int = 5 * 1024 * 1024,
        maxFiles: Int = 5,
    ) {
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles

        let base = directory ?? Self.defaultBaseDirectory()
        logDirectory = Self.logDirectory(baseDirectory: base)
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
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
            try? fileManager.removeItem(at: logFileURL)
            for index in 1 ... maxFiles {
                try? fileManager.removeItem(at: rotatedFileURL(index: index))
            }
        }
    }

    public func flush() {
        queue.sync {}
    }

    public func clearLegacyCacheDirectory() {
        queue.sync {
            guard let legacyDirectory = Self.legacyCacheLogDirectory() else { return }
            guard legacyDirectory.standardizedFileURL != logDirectory.standardizedFileURL else { return }
            try? fileManager.removeItem(at: legacyDirectory)
        }
    }

    private func formattedLine(level: LogLevel, category: String, message: String) -> Data {
        let timestamp = timestampFormatter.string(from: Date())
        return Data("\(timestamp) [\(level.rawValue)] [\(category)] \(message)\n".utf8)
    }

    private func ensureLogFileExists() throws {
        guard !fileManager.fileExists(atPath: logFileURL.path) else { return }
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
    }

    private func rotateIfNeeded() throws {
        let attributes = try fileManager.attributesOfItem(atPath: logFileURL.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue >= maxFileSize else { return }

        for index in stride(from: maxFiles - 1, through: 1, by: -1) {
            let source = rotatedFileURL(index: index)
            let destination = rotatedFileURL(index: index + 1)
            try? fileManager.removeItem(at: destination)
            try? fileManager.moveItem(at: source, to: destination)
        }

        let first = rotatedFileURL(index: 1)
        try? fileManager.removeItem(at: first)
        try fileManager.moveItem(at: logFileURL, to: first)
        fileManager.createFile(atPath: logFileURL.path, contents: nil)
    }

    func rotatedFileURL(index: Int) -> URL {
        logDirectory.appendingPathComponent("\(logFileName).\(index)")
    }

    static func defaultBaseDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static func legacyCacheLogDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return logDirectory(baseDirectory: base)
    }

    static func logDirectory(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent("Logs", isDirectory: true)
    }
}
