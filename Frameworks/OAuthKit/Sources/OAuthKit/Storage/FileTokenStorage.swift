import Foundation

public class FileTokenStorage: TokenStorage {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.oauthkit.file-storage", attributes: .concurrent)

    public init(fileName: String = "oauth_token.json") {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let documentsURL = URL(fileURLWithPath: documentsPath)
        fileURL = documentsURL.appendingPathComponent(fileName)
    }

    public func store(_ token: OAuthToken) async throws {
        let data = try JSONEncoder().encode(token)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async(flags: .barrier) {
                do {
                    try data.write(to: self.fileURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func retrieve() async throws -> OAuthToken? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OAuthToken?, Error>) in
            queue.async {
                do {
                    guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let data = try Data(contentsOf: self.fileURL)
                    let token = try JSONDecoder().decode(OAuthToken.self, from: data)
                    continuation.resume(returning: token)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func clear() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async(flags: .barrier) {
                try? FileManager.default.removeItem(at: self.fileURL)
                continuation.resume()
            }
        }
    }
}
