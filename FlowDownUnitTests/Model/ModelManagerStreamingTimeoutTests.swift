import ChatClientKit
@testable import FlowDown
import Foundation
import ServerEvent
import Testing

struct ModelManagerStreamingTimeoutTests {
    @Test
    func `model replies may stream for fifteen minutes`() {
        #expect(ModelManager.streamingTimeout == 900)
    }

    @Test
    func `remote chat clients stream through the fifteen minute event source`() throws {
        let dependencies = ModelManager.remoteChatClientDependencies
        let factory = try #require(dependencies.eventSourceFactory as? StreamingEventSourceFactory)

        #expect(factory.timeoutInterval == 900)
        #expect(factory.makeEventSource().timeoutInterval == 900)
    }

    @Test
    func `streaming data task keeps the request unchanged`() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.com/v1/chat/completions")))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)

        let task = StreamingEventSourceFactory(timeoutInterval: ModelManager.streamingTimeout)
            .makeDataTask(for: request)
        let streamingTask = try #require(task as? StreamingEventStreamTask)

        #expect(streamingTask.dataTask.urlRequest == request)
    }
}
