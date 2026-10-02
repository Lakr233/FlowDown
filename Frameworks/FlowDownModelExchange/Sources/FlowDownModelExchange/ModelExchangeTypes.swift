import CryptoKit
import Foundation

public nonisolated enum ModelExchangeAPI {
    public nonisolated static let signatureHeader = "X-FlowDown-Signature"

    public nonisolated static func sign(path: String, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let digest = sha256(path)
        let signature = try privateKey.signature(for: digest)
        return Data(signature).base64EncodedString()
    }

    public nonisolated static func verify(
        path: String,
        signature: String,
        publicKey: Curve25519.Signing.PublicKey
    ) -> Bool {
        guard let data = Data(base64Encoded: signature) else { return false }
        return publicKey.isValidSignature(data, for: sha256(path))
    }

    public nonisolated static func canonicalPath(from url: URL) -> String {
        let path = url.path.isEmpty ? "/\(url.lastPathComponent)" : url.path
        guard let query = url.query, !query.isEmpty else { return path }
        return "\(path)?\(query)"
    }

    private nonisolated static func sha256(_ input: String) -> Data {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest)
    }
}

public nonisolated enum ModelExchangeCapability: String, CaseIterable, Codable, Sendable {
    case audio
    case visual
    case tool
    case developerRole
}

public nonisolated struct ModelExchangePublicKey: Sendable, Equatable, Codable {
    public let signing: Data
    public let agreement: Data

    public nonisolated init(signing: Curve25519.Signing.PublicKey, agreement: Curve25519.KeyAgreement.PublicKey) {
        self.signing = signing.rawRepresentation
        self.agreement = agreement.rawRepresentation
    }

    public nonisolated init?(encoded: String) {
        guard let data = Data(base64Encoded: encoded), data.count == 64 else { return nil }
        signing = data.prefix(32)
        agreement = data.suffix(32)
    }

    public nonisolated var encoded: String {
        var container = Data()
        container.append(signing)
        container.append(agreement)
        return container.base64EncodedString()
    }

    public nonisolated var signingKey: Curve25519.Signing.PublicKey? {
        try? .init(rawRepresentation: signing)
    }

    public nonisolated var agreementKey: Curve25519.KeyAgreement.PublicKey? {
        try? .init(rawRepresentation: agreement)
    }
}

public nonisolated struct ModelExchangeKeyPair: Sendable {
    public nonisolated let signing: Curve25519.Signing.PrivateKey
    public nonisolated let agreement: Curve25519.KeyAgreement.PrivateKey

    public nonisolated init() {
        signing = .init()
        agreement = .init()
    }

    public nonisolated init?(seed: Data) {
        guard seed.count == 32,
              let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed),
              let agreement = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: seed)
        else { return nil }
        self.signing = signing
        self.agreement = agreement
    }

    public nonisolated var publicKey: ModelExchangePublicKey {
        .init(signing: signing.publicKey, agreement: agreement.publicKey)
    }

    public nonisolated var encodedPublicKey: String {
        publicKey.encoded
    }

    public nonisolated func sign(path: String) throws -> String {
        try ModelExchangeAPI.sign(path: path, privateKey: signing)
    }
}

public nonisolated struct ModelExchangeSignedRequest: Sendable {
    public nonisolated let url: URL
    public nonisolated let headers: [String: String]
}

public nonisolated struct ModelExchangeRequestBuilder: Sendable {
    public nonisolated let flowdownScheme: String
    public nonisolated let callbackScheme: String
    public nonisolated let keyPair: ModelExchangeKeyPair

    public nonisolated init(
        flowdownScheme: String = "flowdown",
        callbackScheme: String,
        keyPair: ModelExchangeKeyPair
    ) {
        self.flowdownScheme = flowdownScheme
        self.callbackScheme = callbackScheme
        self.keyPair = keyPair
    }

    public nonisolated func makeHandshakeURL() -> URL? {
        var components = makeRouteComponents()
        components.queryItems = [
            .init(name: "pk", value: keyPair.encodedPublicKey),
            .init(name: "callback", value: callbackScheme),
        ]
        return components.url
    }

    public nonisolated func makeExchangeURL(
        session: String,
        appName: String,
        reason: String,
        capabilities: [ModelExchangeCapability],
        multipleSelection: Bool,
        timestamp: Date = .init(),
    ) throws -> ModelExchangeSignedRequest {
        var components = makeRouteComponents()
        let caps = capabilities.map(\.rawValue).joined(separator: ",")
        components.queryItems = [
            .init(name: "session", value: session),
            .init(name: "app_name", value: appName),
            .init(name: "reason", value: reason),
            .init(name: "capabilities", value: caps),
            .init(name: "multiple_selection", value: multipleSelection ? "true" : "false"),
            .init(name: "timestamp", value: String(Int(timestamp.timeIntervalSince1970))),
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let path = ModelExchangeAPI.canonicalPath(from: url)
        let signature = try keyPair.sign(path: path)
        var items = components.queryItems ?? []
        items.append(.init(name: "sig", value: signature))
        components.queryItems = items
        guard let finalURL = components.url else { throw URLError(.badURL) }
        let header = [ModelExchangeAPI.signatureHeader: signature]
        return .init(url: finalURL, headers: header)
    }

    private nonisolated func makeRouteComponents() -> URLComponents {
        var components = URLComponents()
        components.scheme = flowdownScheme
        components.host = ModelExchangeURL.routeHost
        components.path = ModelExchangeURL.routePath
        return components
    }
}
