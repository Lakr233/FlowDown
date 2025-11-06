import Foundation

public protocol TokenStorage {
    func store(_ token: OAuthToken) async throws
    func retrieve() async throws -> OAuthToken?
    func clear() async
}

public class MemoryTokenStorage: TokenStorage {
    private var token: OAuthToken?
    private let queue = DispatchQueue(label: "com.oauthkit.memory-storage", attributes: .concurrent)

    public init() {}

    public func store(_ token: OAuthToken) async throws {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.token = token
                continuation.resume()
            }
        }
    }

    public func retrieve() async throws -> OAuthToken? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.token)
            }
        }
    }

    public func clear() async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.token = nil
                continuation.resume()
            }
        }
    }
}
