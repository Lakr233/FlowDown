@testable import FlowDown
import Foundation
import Testing

struct HuggingFaceAPITests {
    @Test
    func `decode files filters directories and keeps file metadata`() throws {
        let data = Data(
            """
            [
              {
                "type": "directory",
                "path": "weights"
              },
              {
                "type": "file",
                "size": 1519,
                "path": ".gitattributes"
              },
              {
                "type": "file",
                "size": 278064920,
                "path": "model.safetensors"
              },
              {
                "type": "file",
                "path": "tokenizer.json"
              }
            ]
            """.utf8,
        )

        let files = try HuggingFaceAPI().decodeFiles(from: data)

        #expect(files.map(\.path) == [".gitattributes", "model.safetensors", "tokenizer.json"])
        #expect(files.map(\.size) == [1519, 278_064_920, nil])
    }

    @Test
    func `total size ignores missing sizes`() {
        let files = [
            HuggingFaceRepositoryFile(type: "file", size: 1519, path: ".gitattributes"),
            HuggingFaceRepositoryFile(type: "file", size: 278_064_920, path: "model.safetensors"),
            HuggingFaceRepositoryFile(type: "file", size: nil, path: "tokenizer.json"),
        ]

        let totalSize = HuggingFaceAPI().totalSize(of: files)

        #expect(totalSize == 278_066_439)
    }
}
