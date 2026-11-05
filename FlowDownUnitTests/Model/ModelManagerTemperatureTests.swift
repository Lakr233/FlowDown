@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Storage
import Testing

/// There is no app-wide temperature: a request carries one only when the
/// model's own Extra Body sets it.
@Suite(.serialized)
struct ModelManagerTemperatureTests {
    @Test
    func `request omits temperature when the model sets none`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let capture = try await captureRequest(bodyFields: "")

        #expect(capture.body.temperature == nil)
        #expect(capture.fields["temperature"] == nil)
        let json = try encodedRequestJSON(capture)
        #expect(json["temperature"] == nil)
    }

    @Test
    func `request uses the temperature from the model's extra body`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let capture = try await captureRequest(bodyFields: #"{"temperature":0.2}"#)

        #expect(capture.body.temperature == nil)
        let json = try encodedRequestJSON(capture)
        #expect(json["temperature"] as? Double == 0.2)
    }

    @Test
    func `request ignores a stored value of the retired global temperature`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let keys = ["Model.Inference.Prompt.Temperature", "CONFKIT.Model.Inference.Temperature"]
        let previous = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
        for key in keys {
            UserDefaults.standard.set(Data("1.5".utf8), forKey: key)
        }

        let capture = try await captureRequest(bodyFields: "")

        #expect(capture.body.temperature == nil)
        #expect(try encodedRequestJSON(capture)["temperature"] == nil)
    }
}

private extension ModelManagerTemperatureTests {
    struct Capture {
        let body: ChatRequestBody
        let fields: [String: Any]
    }

    final class FieldsBox: @unchecked Sendable {
        var value: [String: Any]?
    }

    func captureRequest(bodyFields: String) async throws -> Capture {
        let manager = ModelManager.shared
        let model = CloudModel(
            deviceId: Storage.deviceId,
            model_identifier: "unit/temperature-\(UUID().uuidString.prefix(8))",
            endpoint: "https://example.invalid/v1/chat/completions",
            bodyFields: bodyFields,
            response_format: .chatCompletions,
        )
        await MainActor.run { manager.insertCloudModel(model) }

        let originalFactory = manager.chatServiceFactory
        let service = ChatServiceSpy()
        let fields = FieldsBox()
        manager.chatServiceFactory = { _, additionalBodyField in
            fields.value = additionalBodyField
            return service
        }
        var failure: (any Error)?
        do {
            _ = try await manager.infer(with: model.id, input: [.user(content: .text("Ping"))])
        } catch {
            failure = error
        }
        manager.chatServiceFactory = originalFactory
        await MainActor.run { manager.removeCloudModel(identifier: model.id) }
        if let failure { throw failure }

        let body = try #require(service.receivedBodies.first)
        return Capture(body: body, fields: try #require(fields.value))
    }

    /// The JSON the chat completions client would send for the captured request.
    func encodedRequestJSON(_ capture: Capture) throws -> [String: Any] {
        let client = RemoteCompletionsChatClient(
            model: "unit/model",
            baseURL: "https://example.invalid",
            path: "/v1/chat/completions",
            additionalBodyField: capture.fields,
        )
        let request = try client.makeURLRequest(body: client.resolve(body: capture.body, stream: true))
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
