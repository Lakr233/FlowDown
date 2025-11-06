import CryptoKit
import Foundation

public enum CryptoUtils {
    public static func generateRandomData(length: Int) -> Data {
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, length, bytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        guard result == errSecSuccess else {
            fatalError("Failed to generate random data")
        }
        return data
    }

    public static func generateRandomString(length: Int) -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0 ..< length).map { _ in characters.randomElement()! })
    }

    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    public static func sha256(_ string: String) -> Data {
        guard let data = string.data(using: .utf8) else {
            return Data()
        }
        return sha256(data)
    }
}
