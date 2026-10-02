import Foundation
import Storage

extension CloudModelEditorController {
    /// Keeps the server model list for the "Select from Server" menu so the menu is built
    /// synchronously. A `UIDeferredMenuElement` fulfilled after its menu has closed makes
    /// Catalyst rebuild a menu it already freed and crash (#221, #243), so no menu completion
    /// may wait on the network. Each `load` returns the last list for the same inputs and
    /// starts at most one refresh; a late result only updates this state.
    @MainActor
    final class ServerModelListLoader {
        /// The inputs `ModelManager.fetchModelList` reads. A change drops the cached list.
        struct Request: Hashable {
            var modelID: CloudModel.ID
            var endpoint: String
            var modelListEndpoint: String
            var token: String
            var headers: [String: String]
        }

        enum State: Equatable {
            case loading
            case loaded([String])
        }

        typealias Fetch = @MainActor (CloudModel.ID, @escaping @MainActor ([String]) -> Void) -> Void

        private let fetch: Fetch
        private var request: Request?
        private var state: State = .loading
        private var isFetching = false
        private var generation = 0

        init(fetch: @escaping Fetch = ServerModelListLoader.fetchFromServer) {
            self.fetch = fetch
        }

        /// Returns what the menu should show now and refreshes the list in the background.
        func load(_ request: Request) -> State {
            if request != self.request {
                self.request = request
                state = .loading
                isFetching = false
            }
            if !isFetching {
                isFetching = true
                generation += 1
                let currentGeneration = generation
                fetch(request.modelID) { [weak self] list in
                    guard let self, self.generation == currentGeneration else { return }
                    isFetching = false
                    state = .loaded(list)
                }
            }
            return state
        }

        nonisolated static func fetchFromServer(
            _ identifier: CloudModel.ID,
            completion: @escaping @MainActor ([String]) -> Void,
        ) {
            ModelManager.shared.fetchModelList(identifier: identifier) { list in
                // The loader calls this on the main actor, and fetchModelList calls back either
                // synchronously on that caller or from a main-actor task.
                MainActor.assumeIsolated { completion(list) }
            }
        }
    }
}

extension CloudModelEditorController.ServerModelListLoader.Request {
    init(model: CloudModel) {
        self.init(
            modelID: model.id,
            endpoint: model.endpoint,
            modelListEndpoint: model.model_list_endpoint,
            token: model.token,
            headers: model.headers,
        )
    }
}
