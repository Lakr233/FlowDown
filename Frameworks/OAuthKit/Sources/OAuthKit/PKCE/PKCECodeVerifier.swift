import Foundation

public struct PKCECodeVerifier {
    public let value: String

    public init() {
        value = Self.generate()
    }

    public init(value: String) throws {
        guard Self.isValid(value) else {
            throw PKCEError.invalidCodeVerifier
        }
        self.value = value
    }

    private static func generate() -> String {
        let length = Int.random(in: 43 ... 128)
        return CryptoUtils.generateRandomString(length: length)
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isValid(_ value: String) -> Bool {
        let validCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let invalidCharacters = CharacterSet(charactersIn: value).subtracting(validCharacters)
        return value.count >= 43 && value.count <= 128 && invalidCharacters.isEmpty
    }
}

public enum PKCEError: Error {
    case invalidCodeVerifier
    case invalidCodeChallenge
    case challengeGenerationFailed
}
