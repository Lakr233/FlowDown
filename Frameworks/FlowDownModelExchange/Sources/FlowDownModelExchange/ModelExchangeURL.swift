import Foundation

public nonisolated enum ModelExchangeURL {
    nonisolated static let routeHost = "models"
    nonisolated static let routePath = "/exchange"

    public nonisolated struct Handshake: Sendable {
        public let publicKey: String
        public let callbackScheme: String
    }

    public nonisolated struct Exchange: Sendable {
        public let session: String
        public let appName: String
        public let reason: String
        public let capabilities: [ModelExchangeCapability]
        public let multipleSelection: Bool
        public let timestamp: Date
        public let signature: String?
    }

    public nonisolated enum Stage: Sendable {
        case handshake(Handshake)
        case exchange(Exchange)
        case cancelled(session: String?)
    }

    public nonisolated static func resolve(_ url: URL) -> Stage? {
        guard let host = url.host?.lowercased(), host == routeHost else { return nil }
        guard url.path.lowercased() == routePath else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        let dict = Dictionary(
            items.compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name.lowercased(), value)
            },
            uniquingKeysWith: { first, _ in first }
        )

        if let stage = dict["stage"], stage.lowercased() == "cancelled" {
            return .cancelled(session: dict["session"])
        }

        if let pk = dict["pk"], let callback = dict["callback"], !pk.isEmpty, !callback.isEmpty {
            return .handshake(.init(publicKey: pk, callbackScheme: callback))
        }

        guard let session = dict["session"],
              let appName = dict["app_name"],
              let reason = dict["reason"],
              let multipleSelection = dict["multiple_selection"].flatMap({ $0.lowercased() == "true" }),
              let timestampString = dict["timestamp"],
              let timestampValue = TimeInterval(timestampString)
        else { return nil }

        let rawCapabilities = dict["capabilities"] ?? ""
        let rawList = rawCapabilities.split(separator: ",").map(String.init)
        let caps = rawList.compactMap { ModelExchangeCapability(rawValue: $0) }
        if caps.count != rawList.count { return nil }
        let signature = dict["sig"]
        let exchange = Exchange(
            session: session,
            appName: appName,
            reason: reason,
            capabilities: caps,
            multipleSelection: multipleSelection,
            timestamp: Date(timeIntervalSince1970: timestampValue),
            signature: signature,
        )
        return .exchange(exchange)
    }
}
