import Foundation

public struct OAuthToken: Codable, Equatable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: TimeInterval?
    public let refreshToken: String?
    public let scope: String?
    public let idToken: String?
    private let issuedAt: Date

    public init(
        accessToken: String,
        tokenType: String = "Bearer",
        expiresIn: TimeInterval? = nil,
        refreshToken: String? = nil,
        scope: String? = nil,
        idToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.idToken = idToken
        issuedAt = Date()
    }

    public var isExpired: Bool {
        guard let expiresIn else {
            return false
        }
        return Date().timeIntervalSince(issuedAt) >= expiresIn
    }

    public var expirationDate: Date? {
        guard let expiresIn else {
            return nil
        }
        return issuedAt.addingTimeInterval(expiresIn)
    }

    public var authorizationHeader: String {
        "\(tokenType) \(accessToken)"
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case idToken = "id_token"
        case issuedAt = "issued_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        expiresIn = try container.decodeIfPresent(TimeInterval.self, forKey: .expiresIn)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        idToken = try container.decodeIfPresent(String.self, forKey: .idToken)

        // If issued_at is not present in the response, use current time
        if let issuedAtTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .issuedAt) {
            issuedAt = Date(timeIntervalSince1970: issuedAtTimestamp)
        } else {
            issuedAt = Date()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(expiresIn, forKey: .expiresIn)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(idToken, forKey: .idToken)
        try container.encode(issuedAt.timeIntervalSince1970, forKey: .issuedAt)
    }
}
