import Foundation
@testable import Logger
import Testing

struct LogStoreTests {
    @Test
    func `default base directory resolves to documents directory`() {
        let expected = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let resolved = LogStore.defaultBaseDirectory()

        #expect(resolved.standardizedFileURL == expected.standardizedFileURL)
    }

    @Test
    func `log directory helper appends Logs folder to base directory`() {
        let base = URL(filePath: "/tmp/flowdown-log-tests", directoryHint: .isDirectory)

        let resolved = LogStore.logDirectory(baseDirectory: base)

        #expect(resolved.path == "/tmp/flowdown-log-tests/Logs")
    }

    @Test
    func `append writes formatted line and readTail returns it`() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.append(level: .info, category: "Tests", message: "hello world")
        store.flush()

        let text = store.readTail()
        #expect(text.contains("[INFO]"))
        #expect(text.contains("[Tests]"))
        #expect(text.contains("hello world"))
    }

    @Test
    func `readTail limits output to requested byte count`() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let message = String(repeating: "x", count: 40)
        for index in 0 ..< 5 {
            store.append(level: .debug, category: "Tail", message: "\(index)-\(message)")
        }
        store.flush()

        let tail = store.readTail(maxBytes: 128)
        #expect(!tail.contains("0-"))
        #expect(tail.contains("4-"))
        #expect(tail.count <= 200) // guard against unexpectedly large tails
    }

    @Test
    func readTail_cutInsideMultibyteCharacter_returnsTail() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.append(level: .info, category: "Tail", message: String(repeating: "中", count: 100))
        store.flush()

        for maxBytes in 10 ... 12 {
            #expect(store.readTail(maxBytes: maxBytes) == "中中中\n")
        }
    }

    @Test
    func `log files rotate once max size is reached`() throws {
        let (store, directory) = try makeStore(maxFileSize: 128, maxFiles: 2)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = FileManager.default

        for index in 0 ..< 12 {
            store.append(level: .info, category: "Rotate", message: "line-\(index)")
        }
        store.flush()

        #expect(manager.fileExists(atPath: store.logFileURL.path))
        #expect(manager.fileExists(atPath: store.rotatedFileURL(index: 1).path))
        #expect(manager.fileExists(atPath: store.rotatedFileURL(index: 2).path))
        #expect(!manager.fileExists(atPath: store.rotatedFileURL(index: 3).path))
    }

    @Test
    func `rotate keeps newest content in base file after rolling over`() throws {
        let (store, directory) = try makeStore(maxFileSize: 96, maxFiles: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0 ..< 6 { // likely triggers rotation at least once
            store.append(level: .info, category: "Rotate", message: "entry-\(index)")
        }
        // Write once more after rotation to ensure base file has fresh content
        store.append(level: .info, category: "Rotate", message: "latest-entry")
        store.flush()

        let tail = store.readTail(maxBytes: 256)
        #expect(tail.contains("latest-entry"))
    }

    @Test
    func `clear removes files even after rotation happened`() throws {
        let (store, directory) = try makeStore(maxFileSize: 96, maxFiles: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0 ..< 6 {
            store.append(level: .info, category: "Rotate", message: "entry-\(index)")
        }
        store.flush()

        store.clear()

        let contents = (try? FileManager.default.contentsOfDirectory(at: store.logDirectory, includingPropertiesForKeys: nil)) ?? []
        #expect(contents.isEmpty)
    }

    @Test
    func `readTail returns empty string when file does not exist`() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        store.clear()
        let tail = store.readTail()
        #expect(tail.isEmpty)
    }

    @Test
    func `clear removes base and rotated log files`() throws {
        let (store, directory) = try makeStore(maxFileSize: 128, maxFiles: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        store.append(level: .error, category: "Cleanup", message: "boom")
        store.append(level: .error, category: "Cleanup", message: "boom2")
        store.flush()

        store.clear()

        let contents = (try? FileManager.default.contentsOfDirectory(at: store.logDirectory, includingPropertiesForKeys: nil)) ?? []
        #expect(contents.isEmpty)
    }

    @Test
    func `category resolver infers sensible defaults`() {
        #expect(LogCategoryResolver.resolve(fileID: "/tmp/ModelInference.swift") == "Model")
        #expect(LogCategoryResolver.resolve(fileID: "/tmp/NetworkService.swift") == "Network")
        #expect(LogCategoryResolver.resolve(fileID: "/tmp/UserInterfaceView.swift") == "UI")
        #expect(LogCategoryResolver.resolve(fileID: "/tmp/DatabaseManager.swift") == "Database")
        #expect(LogCategoryResolver.resolve(fileID: "/tmp/Other.swift") == "App")
    }
}

private func makeStore(maxFileSize: Int = 512, maxFiles: Int = 3) throws -> (LogStore, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = LogStore(directory: directory, maxFileSize: maxFileSize, maxFiles: maxFiles)
    return (store, directory)
}
