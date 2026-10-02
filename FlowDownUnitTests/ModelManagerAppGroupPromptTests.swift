@preconcurrency @testable import FlowDown
import Foundation
import Testing

struct ModelManagerAppGroupPromptTests {
    @Test
    func `writeSharedAdditionalPrompt writes trimmed text and creates parent folders`() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root
            .appendingPathComponent("a")
            .appendingPathComponent("b")
            .appendingPathComponent("Additional.txt")

        try ModelManager.writeSharedAdditionalPrompt("  Always end with ZZTEST.\n", to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
        let contents = try String(decoding: Data(contentsOf: url), as: UTF8.self)
        #expect(contents == "Always end with ZZTEST.")
    }

    @Test
    func `writeSharedAdditionalPrompt removes the file when the prompt is blank`() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Additional.txt")

        try ModelManager.writeSharedAdditionalPrompt("x", to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        try ModelManager.writeSharedAdditionalPrompt(" \n\t", to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func `writeSharedAdditionalPrompt tolerates a blank prompt with no existing file`() {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root
            .appendingPathComponent("missing")
            .appendingPathComponent("Additional.txt")

        #expect(throws: Never.self) {
            try ModelManager.writeSharedAdditionalPrompt("   ", to: url)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerAppGroupPromptTests-\(UUID().uuidString)")
    }
}
