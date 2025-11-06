import Foundation

public struct PKCECodeChallenge {
    public let value: String
    public let method: Method

    public enum Method: String, CaseIterable {
        case plain
        case sha256 = "S256"
    }

    public init(verifier: PKCECodeVerifier, method: Method = .sha256) throws {
        self.method = method

        switch method {
        case .plain:
            value = verifier.value
        case .sha256:
            let hash = CryptoUtils.sha256(verifier.value)
            value = Base64URL.encode(hash)
        }

        guard !value.isEmpty else {
            throw PKCEError.challengeGenerationFailed
        }
    }
}
