import Foundation

public class PKCESession {
    public let verifier: PKCECodeVerifier
    public let challenge: PKCECodeChallenge
    public let state: String
    private let createdAt: Date

    public init(challengeMethod: PKCECodeChallenge.Method = .sha256) throws {
        verifier = PKCECodeVerifier()
        challenge = try PKCECodeChallenge(verifier: verifier, method: challengeMethod)
        state = CryptoUtils.generateRandomString(length: 32)
        createdAt = Date()
    }

    public var isExpired: Bool {
        let expirationTime: TimeInterval = 600 // 10 minutes
        return Date().timeIntervalSince(createdAt) > expirationTime
    }

    public func validateState(_ receivedState: String) -> Bool {
        state == receivedState
    }
}
