//
//  ModelManager+StreamingTimeout.swift
//  FlowDown
//

import ChatClientKit
import Foundation
import ServerEvent

extension ModelManager {
    /// How long a model reply may stream before the request times out.
    /// Long reasoning models can take well over five minutes to finish an answer.
    static let streamingTimeout: TimeInterval = 15 * 60

    /// The live remote client dependencies, streaming replies under `streamingTimeout`
    /// instead of ChatClientKit's 300 second default.
    static var remoteChatClientDependencies: RemoteClientDependencies {
        var dependencies = RemoteClientDependencies.live
        dependencies.eventSourceFactory = StreamingEventSourceFactory(timeoutInterval: streamingTimeout)
        return dependencies
    }
}

/// Mirrors ChatClientKit's `DefaultEventSourceFactory` with a configurable timeout.
struct StreamingEventSourceFactory: EventSourceProducing {
    let timeoutInterval: TimeInterval

    func makeEventSource() -> EventSource {
        EventSource(timeoutInterval: timeoutInterval)
    }

    func makeDataTask(for request: URLRequest) -> EventStreamTask {
        StreamingEventStreamTask(dataTask: makeEventSource().dataTask(for: request))
    }
}

struct StreamingEventStreamTask: EventStreamTask, @unchecked Sendable {
    let dataTask: EventSource.DataTask

    func events() -> AsyncStream<EventSource.EventType> {
        dataTask.events()
    }
}
