//
//  EventSource.swift
//  EventSource
//
//  Copyright © 2023 Firdavs Khaydarov (Recouse). All rights reserved.
//  Licensed under the MIT License.
//

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

///
/// An `EventSource` instance opens a persistent connection to an HTTP server,
/// which sends events in `text/event-stream` format.
/// The connection remains open until closed by calling `close()`.
///
public struct EventSource: Sendable {
    public enum Mode: Sendable {
        case `default`
        case dataOnly
    }

    /// State of the connection.
    public enum ReadyState: Int, Sendable {
        case none = -1
        case connecting = 0
        case open = 1
        case closed = 2
    }

    /// Event type.
    public enum EventType: Sendable {
        case error(Error)
        case event(EVEvent)
        case open
        case closed
    }

    private let mode: Mode

    private let eventParser: @Sendable () -> EventParser

    public var timeoutInterval: TimeInterval

    public init(mode: Mode = .default, timeoutInterval: TimeInterval = 300) {
        self.init(mode: mode, eventParser: ServerEventParser(mode: mode), timeoutInterval: timeoutInterval)
    }

    public init(
        mode: Mode = .default,
        eventParser: @autoclosure @escaping @Sendable () -> EventParser,
        timeoutInterval: TimeInterval = 300
    ) {
        self.mode = mode
        self.eventParser = eventParser
        self.timeoutInterval = timeoutInterval
    }

    public func dataTask(for urlRequest: URLRequest) -> DataTask {
        DataTask(
            urlRequest: urlRequest,
            eventParser: eventParser(),
            timeoutInterval: timeoutInterval
        )
    }
}

public extension EventSource {
    /// An EventSource task that handles connecting to the URLRequest and creating an event stream.
    ///
    /// Creation of a task is exclusively handled by ``EventSource``. A new task can be created by calling
    /// ``EventSource/EventSource/dataTask(for:)`` method on the EventSource instance. After creating a task,
    /// it can be started by iterating event stream returned by ``DataTask/events()``.
    final class DataTask: Sendable {
        private let _readyState: Mutex<ReadyState> = Mutex(.none)

        /// A value representing the state of the connection.
        public var readyState: ReadyState {
            get {
                _readyState.withLock { $0 }
            }
            set {
                _readyState.withLock { $0 = newValue }
            }
        }

        private let _lastMessageId: Mutex<String> = Mutex("")

        /// Last event's ID string value.
        ///
        /// Sent in a HTTP request header and used when a user is to reestablish the connection.
        public var lastMessageId: String {
            get {
                _lastMessageId.withLock { $0 }
            }
            set {
                _lastMessageId.withLock { $0 = newValue }
            }
        }

        /// A URLRequest of the events source.
        public let urlRequest: URLRequest

        private let _eventParser: Mutex<EventParser>

        private var eventParser: EventParser {
            get {
                _eventParser.withLock { $0 }
            }
            set {
                _eventParser.withLock { $0 = newValue }
            }
        }

        private let timeoutInterval: TimeInterval

        private let _httpResponseErrorStatusCode: Mutex<Int?> = Mutex(nil)

        private var httpResponseErrorStatusCode: Int? {
            get {
                _httpResponseErrorStatusCode.withLock { $0 }
            }
            set {
                _httpResponseErrorStatusCode.withLock { $0 = newValue }
            }
        }

        private let _consumed: Mutex<Bool> = Mutex(false)

        private var consumed: Bool {
            get {
                _consumed.withLock { $0 }
            }
            set {
                _consumed.withLock { $0 = newValue }
            }
        }

        private var urlSessionConfiguration: URLSessionConfiguration {
            let configuration = URLSessionConfiguration.default
            configuration.httpAdditionalHeaders = [
                HTTPHeaderField.accept: Accept.eventStream,
                HTTPHeaderField.cacheControl: CacheControl.noStore,
                HTTPHeaderField.lastEventID: lastMessageId,
            ]
            configuration.timeoutIntervalForRequest = timeoutInterval
            configuration.timeoutIntervalForResource = timeoutInterval
            return configuration
        }

        init(
            urlRequest: URLRequest,
            eventParser: EventParser,
            timeoutInterval: TimeInterval
        ) {
            self.urlRequest = urlRequest
            _eventParser = Mutex(eventParser)
            self.timeoutInterval = timeoutInterval
        }

        /// Creates and returns event stream.
        public func events() -> AsyncStream<EventType> {
            if consumed {
                return AsyncStream { continuation in
                    continuation.yield(.error(EventSourceError.alreadyConsumed))
                    continuation.finish()
                }
            }

            return AsyncStream { continuation in
                let sessionDelegate = SessionDelegate()
                let urlSession = URLSession(
                    configuration: urlSessionConfiguration,
                    delegate: sessionDelegate,
                    delegateQueue: nil
                )
                let urlSessionDataTask = urlSession.dataTask(with: urlRequest)

                let sessionDelegateTask = Task { [weak self] in
                    for await event in sessionDelegate.eventStream {
                        guard let self else { return }

                        switch event {
                        case let .didCompleteWithError(error):
                            handleSessionError(error, stream: continuation, urlSession: urlSession)
                        case let .didReceiveResponse(response, completionHandler):
                            handleSessionResponse(
                                response,
                                stream: continuation,
                                urlSession: urlSession,
                                completionHandler: completionHandler
                            )
                        case let .didReceiveData(data):
                            parseMessages(from: data, stream: continuation, urlSession: urlSession)
                        }
                    }
                }

                #if compiler(>=6.0)
                    continuation.onTermination = { @Sendable [weak self] _ in
                        sessionDelegateTask.cancel()
                        print("[-] cancelling event source dataTask due to task termination")
                        urlSession.invalidateAndCancel()
                        Task { self?.close(stream: continuation, urlSession: urlSession) }
                    }
                #else
                    continuation.onTermination = { @Sendable _ in
                        sessionDelegateTask.cancel()
                        print("[-] cancelling event source dataTask due to task termination")
                        urlSession.invalidateAndCancel()
                        Task { [weak self] in
                            await self?.close(stream: continuation, urlSession: urlSession)
                        }
                    }
                #endif

                urlSessionDataTask.resume()
                readyState = .connecting
                consumed = true
            }
        }

        private func handleSessionError(
            _ error: Error?,
            stream continuation: AsyncStream<EventType>.Continuation,
            urlSession: URLSession
        ) {
            guard readyState != .closed else {
                close(stream: continuation, urlSession: urlSession)
                return
            }

            // Send error event
            if let error {
                sendErrorEvent(with: error, stream: continuation)
            }

            // Close connection
            close(stream: continuation, urlSession: urlSession)
        }

        private func handleSessionResponse(
            _ response: URLResponse,
            stream continuation: AsyncStream<EventType>.Continuation,
            urlSession: URLSession,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard readyState != .closed else {
                completionHandler(.cancel)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completionHandler(.cancel)
                return
            }

            // Stop connection when 204 response code, otherwise keep open
            guard httpResponse.statusCode != 204 else {
                completionHandler(.cancel)
                close(stream: continuation, urlSession: urlSession)
                return
            }

            if 200 ... 299 ~= httpResponse.statusCode {
                if readyState != .open {
                    setOpen(stream: continuation)
                }
            } else {
                httpResponseErrorStatusCode = httpResponse.statusCode
            }

            completionHandler(.allow)
        }

        /// Closes the connection, if one was made,
        /// and sets the `readyState` property to `.closed`.
        /// - Returns: State before closing.
        private func close(stream continuation: AsyncStream<EventType>.Continuation, urlSession: URLSession) {
            let previousState = readyState
            if previousState != .closed {
                continuation.yield(.closed)
                continuation.finish()
            }
            cancel(urlSession: urlSession)
        }

        private func parseMessages(
            from data: Data,
            stream continuation: AsyncStream<EventType>.Continuation,
            urlSession: URLSession
        ) {
            if let httpResponseErrorStatusCode {
                self.httpResponseErrorStatusCode = nil
                handleSessionError(
                    EventSourceError.connectionError(statusCode: httpResponseErrorStatusCode, response: data),
                    stream: continuation,
                    urlSession: urlSession
                )
                return
            }

            let events = eventParser.parse(data)

            // Update last message ID
            if let lastMessageWithId = events.last(where: { $0.id != nil }) {
                lastMessageId = lastMessageWithId.id ?? ""
            }

            for item in events {
                continuation.yield(.event(item))
            }
        }

        private func setOpen(stream continuation: AsyncStream<EventType>.Continuation) {
            readyState = .open
            continuation.yield(.open)
        }

        private func sendErrorEvent(with error: Error, stream continuation: AsyncStream<EventType>.Continuation) {
            continuation.yield(.error(error))
        }

        /// Cancels the task.
        ///
        /// ## Notes:
        /// The event stream supports cooperative task cancellation. However, it should be noted that
        /// canceling the parent Task only cancels the underlying `URLSessionDataTask` of
        /// ``EventSource/EventSource/DataTask``; this does not actually stop the ongoing request.
        public func cancel(urlSession: URLSession) {
            readyState = .closed
            lastMessageId = ""
            urlSession.invalidateAndCancel()
        }
    }
}
