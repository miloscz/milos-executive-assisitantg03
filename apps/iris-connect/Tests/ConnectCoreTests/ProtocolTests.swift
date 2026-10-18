import XCTest
import CryptoKit
import Security
@testable import ConnectCore

final class ProtocolTests: XCTestCase {
    private func client() throws -> LegacyClient {
        try LegacyClient(source: """
        const CLIENT_ID = "test-client";
        const CLIENT_SECRET = "synthetic-client-secret";
        const OIDC_BASE = "\(EndpointPolicy.issuer.absoluteString)";
        """)
    }

    func testLegacyConfigurationDoesNotExecuteSource() throws {
        let c = try client()
        XCTAssertEqual(c.id, "test-client")
        XCTAssertEqual(c.issuer, EndpointPolicy.issuer)
        XCTAssertThrowsError(try LegacyClient(source: "const CLIENT_ID = process.env.SECRET;"))
        XCTAssertThrowsError(try LegacyClient(source: """
        const CLIENT_ID = "test";
        const CLIENT_SECRET = "synthetic";
        const OIDC_BASE = "https://example.com/oidc";
        """))
    }

    func testAuthorizationHasPKCEStateAndNonce() throws {
        let a = LoginAttempt()
        let b = LoginAttempt()
        XCTAssertNotEqual(a.state, b.state); XCTAssertNotEqual(a.verifier, b.verifier); XCTAssertNotEqual(a.nonce, b.nonce)
        let items = URLComponents(url: try a.authorizationURL(client: client()), resolvingAgainstBaseURL: false)!.queryItems!
        let parameters = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        XCTAssertEqual(parameters["code_challenge_method"], "S256")
        XCTAssertEqual(parameters["code_challenge"], Data(SHA256.hash(data: Data(a.verifier.utf8))).base64URL)
        XCTAssertEqual(parameters["state"], a.state); XCTAssertEqual(parameters["nonce"], a.nonce)
        XCTAssertNil(parameters["client_secret"]); XCTAssertNil(parameters["accessCode1"])
    }

    func testImportedClientKeepsFixedIssuerAndRejectsInvalidValues() throws {
        let imported = try LegacyClient(id: "synthetic-client", secret: "synthetic-secret")
        XCTAssertEqual(imported.issuer, EndpointPolicy.issuer)
        for pair in [("", "synthetic"), ("synthetic", ""), ("synthetic\nclient", "secret"),
                     ("synthetic", String(repeating: "x", count: 4097))] {
            XCTAssertThrowsError(try LegacyClient(id: pair.0, secret: pair.1))
        }
        XCTAssertThrowsError(try LegacyClient(source: String(repeating: "x", count: 524289)))
    }

    func testCallbackRejectsWrongStateDuplicateAndForeignHost() throws {
        let a = LoginAttempt()
        func url(_ suffix: String) -> URL { URL(string: a.callbackURL.absoluteString + suffix)! }
        XCTAssertEqual(try a.authorizationCode(from: url("?code=synthetic-code&state=\(a.state)")), "synthetic-code")
        for s in ["?code=x&state=wrong", "?code=x&code=y&state=\(a.state)", "?code=x&state=\(a.state)&state=\(a.state)", "?code=x&state=\(a.state)&error=denied", "?code=&state=\(a.state)"] {
            XCTAssertThrowsError(try a.authorizationCode(from: url(s)))
        }
        XCTAssertThrowsError(try a.authorizationCode(from: URL(string: "http://localhost.evil:\(a.callbackURL.port!)/?code=x&state=\(a.state)")!))
        XCTAssertThrowsError(try a.authorizationCode(from: url("?code=x&state=\(a.state)"), now: a.expiresAt.addingTimeInterval(1)))
    }

    func testCredentialInsertionAndEndpointPolicyAreStrict() {
        let root = "https://uuidentity.plus4u.net"
        XCTAssertTrue(EndpointPolicy.allowsCredentialInsertion(URL(string: root + EndpointPolicy.loginPath + "?state=public-state")!))
        for target in ["http://uuidentity.plus4u.net" + EndpointPolicy.loginPath,
                       "https://uuidentity.plus4u.net.evil" + EndpointPolicy.loginPath,
                       "https://uuidentity.plus4u.net:444" + EndpointPolicy.loginPath,
                       root + EndpointPolicy.loginPath + "/registration", root + "/other/login",
                       "https://user@uuidentity.plus4u.net" + EndpointPolicy.loginPath] {
            XCTAssertFalse(EndpointPolicy.allowsCredentialInsertion(URL(string: target)!))
        }
        let endpoint = EndpointPolicy.endpoint("getIdentity")
        XCTAssertTrue(EndpointPolicy.allows(endpoint, path: endpoint.path))
        XCTAssertFalse(EndpointPolicy.allows(URL(string: endpoint.absoluteString + "?redirect=https://example.com")!, path: endpoint.path))
    }

    func testRealRS256SignatureAndClaimsValidation() throws {
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        let privateKey = try XCTUnwrap(SecKeyCreateRandomKey(attrs as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let components = try rsaComponents(der)
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kid": "fixture", "kty": "RSA", "alg": "RS256", "use": "sig", "n": components.0.base64URL, "e": components.1.base64URL]]])
        let now = Date()
        let claims: [String: Any] = ["iss": EndpointPolicy.issuer.absoluteString, "aud": "test-client", "sub": "synthetic-subject", "nonce": "fixture-nonce", "iat": now.timeIntervalSince1970, "exp": now.addingTimeInterval(600).timeIntervalSince1970]
        func signed(_ claims: [String: Any], algorithm: String = "RS256") throws -> String {
            let h = try JSONSerialization.data(withJSONObject: ["alg": algorithm, "kid": "fixture"]).base64URL
            let p = try JSONSerialization.data(withJSONObject: claims).base64URL
            let message = Data((h + "." + p).utf8)
            let signature = try XCTUnwrap(SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, nil) as Data?)
            return h + "." + p + "." + signature.base64URL
        }
        let good = try signed(claims)
        XCTAssertGreaterThan(try TokenValidation.validate(good, jwks: jwks, clientID: "test-client", nonce: "fixture-nonce"), now)
        XCTAssertThrowsError(try TokenValidation.validate(good, jwks: jwks, clientID: "wrong", nonce: "fixture-nonce"))
        XCTAssertThrowsError(try TokenValidation.validate(good, jwks: jwks, clientID: "test-client", nonce: "wrong"))
        XCTAssertThrowsError(try TokenValidation.validate(good, jwks: jwks, clientID: "wrong", nonce: "wrong")) { error in
            XCTAssertEqual((error as? TokenRejection)?.reasons, [.tokenAudience, .tokenNonce])
        }
        // uuOIDC can include issuer + client audiences without an azp extension.
        var multi = claims
        multi["aud"] = ["test-client", EndpointPolicy.issuer.absoluteString]
        XCTAssertNoThrow(try TokenValidation.validate(signed(multi), jwks: jwks, clientID: "test-client", nonce: "fixture-nonce"))
        multi["azp"] = "test-client"
        XCTAssertNoThrow(try TokenValidation.validate(signed(multi), jwks: jwks, clientID: "test-client", nonce: "fixture-nonce"))
        let invalidAuthorizedParties: [Any] = ["another-client", NSNull(), ["test-client"], 42]
        for invalidAZP in invalidAuthorizedParties {
            var bad = multi; bad["azp"] = invalidAZP
            XCTAssertThrowsError(try TokenValidation.validate(signed(bad), jwks: jwks, clientID: "test-client", nonce: "fixture-nonce")) { error in
                XCTAssertEqual((error as? TokenRejection)?.reasons, [.tokenAuthorizedParty])
            }
        }
        var unexpected = multi; unexpected["aud"] = ["test-client", "another-client"]
        XCTAssertThrowsError(try TokenValidation.validate(signed(unexpected), jwks: jwks, clientID: "test-client", nonce: "fixture-nonce")) { error in
            XCTAssertEqual((error as? TokenRejection)?.reasons, [.tokenAudience])
        }
        var callToken = claims; callToken["aud"] = ["test-client", "https://"]
        XCTAssertThrowsError(try TokenValidation.validate(signed(callToken), jwks: jwks, clientID: "test-client", nonce: "fixture-nonce"))
        XCTAssertNoThrow(try TokenValidation.validate(signed(callToken), jwks: jwks, clientID: "test-client", nonce: "fixture-nonce", trustedAdditionalAudiences: ["https://"]))
        for (key, value) in [("iss", "https://example.com" as Any), ("exp", now.addingTimeInterval(-60).timeIntervalSince1970 as Any), ("nbf", now.addingTimeInterval(600).timeIntervalSince1970 as Any), ("aud", ["test-client", "other"] as Any)] {
            var bad = claims; bad[key] = value
            XCTAssertThrowsError(try TokenValidation.validate(signed(bad), jwks: jwks, clientID: "test-client", nonce: "fixture-nonce"))
        }
        XCTAssertThrowsError(try TokenValidation.validate(signed(claims, algorithm: "none"), jwks: jwks, clientID: "test-client", nonce: "fixture-nonce"))
        let pieces = good.split(separator: ".").map(String.init)
        let changed = pieces[0] + "." + Data("{}".utf8).base64URL + "." + pieces[2]
        XCTAssertThrowsError(try TokenValidation.validate(changed, jwks: jwks, clientID: "test-client", nonce: "fixture-nonce"))
    }

    private func rsaComponents(_ der: Data) throws -> (Data, Data) {
        let bytes = [UInt8](der); var index = 0
        func readLength() throws -> Int {
            let b = Int(bytes[index]); index += 1
            if b < 128 { return b }
            var length = 0
            for _ in 0..<(b & 127) { length = length * 256 + Int(bytes[index]); index += 1 }
            return length
        }
        XCTAssertEqual(bytes[index], 0x30); index += 1; _ = try readLength()
        func integer() throws -> Data {
            XCTAssertEqual(bytes[index], 2); index += 1
            let length = try readLength(); let data = Data(bytes[index..<(index + length)]); index += length
            return Data(data.drop(while: { $0 == 0 }))
        }
        return try (integer(), integer())
    }
}
