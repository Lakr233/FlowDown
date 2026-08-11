@testable import FlowDown
import Foundation
import Storage
import Testing

struct ModelScopeTests {
    @Test
    func `cloud model response format inference normalizes endpoints`() {
        let missingFormat: CloudModel.ResponseFormat? = nil

        #expect(
            CloudModel.ResponseFormat.inferredFormat(
                fromEndpoint: " HTTPS://api.example.com/v1/chat/completions/?query=1#fragment ",
            ) == .chatCompletions,
        )
        #expect(
            CloudModel.ResponseFormat.inferredFormat(
                fromEndpoint: "https://api.example.com/responses/",
            ) == .responses,
        )
        #expect(CloudModel.ResponseFormat.inferredFormat(fromEndpoint: "") == missingFormat)
        #expect(CloudModel.ResponseFormat.chatCompletions.defaultModelListEndpoint == "$INFERENCE_ENDPOINT$/../../models")
        #expect(CloudModel.ResponseFormat.responses.defaultModelListEndpoint == "$INFERENCE_ENDPOINT$/../models")
    }

    @Test
    func `hub download progress tracks file completion and cancellation`() {
        let progress = ModelManager.HubDownloadProgress()
        progress.acquiredFileList(["a.bin", "b.bin"])

        #expect(progress.progressMap.keys.sorted() == ["a.bin", "b.bin"])
        #expect(progress.progressMap["a.bin"]?.completedUnitCount == 0)
        #expect(progress.progressMap["a.bin"]?.totalUnitCount == 100)

        progress.completeFile("a.bin", size: 64)
        progress.finalizeDownload()

        #expect(progress.progressMap["a.bin"]?.completedUnitCount == 64)
        #expect(progress.progressMap["b.bin"]?.completedUnitCount == progress.progressMap["b.bin"]?.totalUnitCount)

        progress.isCancelled = true

        var didThrow = false
        do {
            try progress.checkContinue()
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}
