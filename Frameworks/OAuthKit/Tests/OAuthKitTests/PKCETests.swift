@testable import OAuthKit
import XCTest

final class PKCETests: XCTestCase {
    func testCodeVerifierGeneration() throws {
        let verifier = PKCECodeVerifier()

        XCTAssertGreaterThanOrEqual(verifier.value.count, 43)
        XCTAssertLessThanOrEqual(verifier.value.count, 128)

        let validCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let invalidCharacters = CharacterSet(charactersIn: verifier.value).subtracting(validCharacters)
        XCTAssertTrue(invalidCharacters.isEmpty)
    }

    func testCodeVerifierValidation() throws {
        let validVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertNoThrow(try PKCECodeVerifier(value: validVerifier))

        let tooShort = "short"
        XCTAssertThrowsError(try PKCECodeVerifier(value: tooShort)) { error in
            XCTAssertEqual(error as? PKCEError, PKCEError.invalidCodeVerifier)
        }

        let tooLong = String(repeating: "a", count: 129)
        XCTAssertThrowsError(try PKCECodeVerifier(value: tooLong)) { error in
            XCTAssertEqual(error as? PKCEError, PKCEError.invalidCodeVerifier)
        }

        let invalidChars = "invalid+chars/"
        XCTAssertThrowsError(try PKCECodeVerifier(value: invalidChars)) { error in
            XCTAssertEqual(error as? PKCEError, PKCEError.invalidCodeVerifier)
        }
    }

    func testCodeChallengeGeneration() throws {
        let verifier = try PKCECodeVerifier(value: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        let challengePlain = try PKCECodeChallenge(verifier: verifier, method: .plain)
        XCTAssertEqual(challengePlain.value, verifier.value)
        XCTAssertEqual(challengePlain.method, .plain)

        let challengeSHA256 = try PKCECodeChallenge(verifier: verifier, method: .sha256)
        XCTAssertEqual(challengeSHA256.value, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(challengeSHA256.method, .sha256)
    }

    func testPKCESession() throws {
        let session = try PKCESession()

        XCTAssertFalse(session.isExpired)
        XCTAssertEqual(session.state.count, 32)
        XCTAssertGreaterThanOrEqual(session.verifier.value.count, 43)
        XCTAssertLessThanOrEqual(session.verifier.value.count, 128)

        XCTAssertTrue(session.validateState(session.state))
        XCTAssertFalse(session.validateState("invalid-state"))
    }

    func testBase64URLEncoding() {
        let testData = "hello world".data(using: .utf8)!
        let encoded = Base64URL.encode(testData)

        XCTAssertEqual(encoded, "aGVsbG8gd29ybGQ")
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))

        let decoded = Base64URL.decode(encoded)
        XCTAssertEqual(decoded, testData)
    }

    func testCryptoUtils() {
        let randomData = CryptoUtils.generateRandomData(length: 32)
        XCTAssertEqual(randomData.count, 32)

        let randomString = CryptoUtils.generateRandomString(length: 64)
        XCTAssertEqual(randomString.count, 64)

        let testString = "hello world"
        let hash = CryptoUtils.sha256(testString)
        XCTAssertEqual(hash.count, 32) // SHA256 produces 32 bytes
    }
}
