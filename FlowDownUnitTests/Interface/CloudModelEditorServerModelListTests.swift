@testable import FlowDown
import Foundation
import Testing

@MainActor
struct CloudModelEditorServerModelListTests {
    typealias Loader = CloudModelEditorController.ServerModelListLoader

    @Test
    func serverModelListLoad_firstRequest_reportsLoadingAndFetchesOnce() {
        let spy = ServerModelListFetchSpy()
        let loader = Loader(fetch: spy.fetch)

        #expect(loader.load(makeRequest()) == .loading)
        #expect(spy.identifiers == ["model"])
    }

    @Test
    func serverModelListLoad_whileFetching_doesNotStartAnotherFetch() {
        let spy = ServerModelListFetchSpy()
        let loader = Loader(fetch: spy.fetch)
        let request = makeRequest()

        _ = loader.load(request)

        #expect(loader.load(request) == .loading)
        #expect(spy.identifiers.count == 1)
    }

    @Test
    func serverModelListLoad_afterCompletion_returnsListAndRefreshesInBackground() {
        let spy = ServerModelListFetchSpy()
        let loader = Loader(fetch: spy.fetch)
        let request = makeRequest()

        _ = loader.load(request)
        spy.complete(call: 0, with: ["a/x", "b"])

        #expect(loader.load(request) == .loaded(["a/x", "b"]))
        #expect(spy.identifiers.count == 2)
    }

    @Test
    func serverModelListLoad_requestInputsChange_ignoresStaleCompletion() {
        let spy = ServerModelListFetchSpy()
        let loader = Loader(fetch: spy.fetch)
        let first = makeRequest(endpoint: "https://old.example.com/v1/chat/completions")
        let second = makeRequest(endpoint: "https://new.example.com/v1/chat/completions")

        _ = loader.load(first)
        #expect(loader.load(second) == .loading)
        #expect(spy.identifiers.count == 2)

        spy.complete(call: 0, with: ["old"])
        #expect(loader.load(second) == .loading)
        #expect(spy.identifiers.count == 2)

        spy.complete(call: 1, with: ["new"])
        #expect(loader.load(second) == .loaded(["new"]))
    }

    @Test
    func serverModelListLoad_tokenChange_dropsCachedList() {
        let spy = ServerModelListFetchSpy()
        let loader = Loader(fetch: spy.fetch)
        let first = makeRequest(token: "old-token")

        _ = loader.load(first)
        spy.complete(call: 0, with: ["cached"])

        #expect(loader.load(makeRequest(token: "new-token")) == .loading)
    }

    @Test
    func serverModelListLoad_synchronousEmptyCompletion_returnsLoadedEmptyImmediately() {
        let loader = Loader { _, completion in completion([]) }

        #expect(loader.load(makeRequest()) == .loaded([]))
    }

    private func makeRequest(
        endpoint: String = "https://api.example.com/v1/chat/completions",
        token: String = "token",
    ) -> Loader.Request {
        .init(
            modelID: "model",
            endpoint: endpoint,
            modelListEndpoint: "$INFERENCE_ENDPOINT$/../../models",
            token: token,
            headers: [:],
        )
    }
}

@MainActor
private final class ServerModelListFetchSpy {
    private(set) var identifiers: [String] = []
    private var completions: [@MainActor ([String]) -> Void] = []

    func fetch(_ identifier: String, completion: @escaping @MainActor ([String]) -> Void) {
        identifiers.append(identifier)
        completions.append(completion)
    }

    func complete(call index: Int, with list: [String]) {
        completions[index](list)
    }
}
