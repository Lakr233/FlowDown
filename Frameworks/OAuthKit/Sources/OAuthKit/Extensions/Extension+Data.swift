import Foundation

extension Data {
    var urlSafeBase64EncodedString: String {
        Base64URL.encode(self)
    }

    init?(urlSafeBase64Encoded string: String) {
        guard let data = Base64URL.decode(string) else {
            return nil
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}
