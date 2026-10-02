import CryptoKit
import Foundation

public nonisolated struct ModelExchangeEncryptedPayload: Codable, Equatable, Sendable {
    public nonisolated let session: String
    public nonisolated let sealed: String
    public nonisolated let ephemeralPublicKey: String

    public nonisolated init(session: String, sealed: String, ephemeralPublicKey: String) {
        self.session = session
        self.sealed = sealed
        self.ephemeralPublicKey = ephemeralPublicKey
    }

    public nonisolated func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
    }

    public nonisolated static func decode(from string: String) throws -> ModelExchangeEncryptedPayload {
        guard let data = Data(base64Encoded: string) else { throw URLError(.cannotDecodeContentData) }
        return try JSONDecoder().decode(ModelExchangeEncryptedPayload.self, from: data)
    }
}

public nonisolated enum ModelExchangeCrypto {
    private nonisolated static let hkdfSalt = Data("flowdown-model-exchange".utf8)

    public nonisolated static func encrypt(
        _ data: Data,
        for peer: ModelExchangePublicKey,
        session: String,
    ) throws -> ModelExchangeEncryptedPayload {
        guard let agreementKey = peer.agreementKey else { throw URLError(.cannotDecodeContentData) }
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: agreementKey)
        let symmetric = deriveKey(secret: secret, session: session, peerSigning: peer.signing)
        let sealedBox = try ChaChaPoly.seal(data, using: symmetric)
        return .init(
            session: session,
            sealed: sealedBox.combined.base64EncodedString(),
            ephemeralPublicKey: ephemeral.publicKey.rawRepresentation.base64EncodedString(),
        )
    }

    public nonisolated static func decrypt(
        _ payload: ModelExchangeEncryptedPayload,
        with keyPair: ModelExchangeKeyPair,
    ) throws -> Data {
        guard let sealedData = Data(base64Encoded: payload.sealed),
              let sealedBox = try? ChaChaPoly.SealedBox(combined: sealedData),
              let peerPublicData = Data(base64Encoded: payload.ephemeralPublicKey),
              let peerPublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicData)
        else {
            throw URLError(.cannotDecodeRawData)
        }

        let secret = try keyPair.agreement.sharedSecretFromKeyAgreement(with: peerPublicKey)
        let symmetric = deriveKey(secret: secret, session: payload.session, peerSigning: keyPair.publicKey.signing)
        return try ChaChaPoly.open(sealedBox, using: symmetric)
    }

    private nonisolated static func deriveKey(
        secret: SharedSecret,
        session: String,
        peerSigning: Data
    ) -> SymmetricKey {
        var salt = hkdfSalt
        salt.append(Data(session.utf8))
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: peerSigning,
            outputByteCount: 32,
        )
    }
}
