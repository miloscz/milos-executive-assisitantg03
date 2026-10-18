import Foundation
import Security

public struct TokenRejection: Error {
    public let reasons: [ConnectFailure]
}

public enum TokenValidation {
    /// Signature and claims are verified before a bearer token is ever used.
    public static func validate(_ token: String, jwks: Data, clientID: String, nonce: String,
                                trustedAdditionalAudiences: Set<String> = [], now: Date = Date()) throws -> Date {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, token.utf8.count <= 65536,
              let h = Data(base64URL: parts[0]), let p = Data(base64URL: parts[1]), let signature = Data(base64URL: parts[2]),
              let header = try? JSONSerialization.jsonObject(with: h) as? [String: Any],
              let claims = try? JSONSerialization.jsonObject(with: p) as? [String: Any],
              header["crit"] == nil,
              let kid = header["kid"] as? String,
              let keys = (try? JSONSerialization.jsonObject(with: jwks) as? [String: Any])?["keys"] as? [[String: Any]] else { throw ConnectFailure.token }
        guard header["alg"] as? String == "RS256" else { throw ConnectFailure.tokenAlgorithm }
        let candidates = keys.filter { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }
        guard candidates.count == 1, let jwk = candidates.first,
              jwk["use"] == nil || jwk["use"] as? String == "sig",
              jwk["alg"] == nil || jwk["alg"] as? String == "RS256",
              let modulus = jwk["n"] as? String, let exponent = jwk["e"] as? String,
              let n = Data(base64URL: modulus), let e = Data(base64URL: exponent), n.count >= 256,
              let key = SecKeyCreateWithData(rsaDER(modulus: n, exponent: e) as CFData,
                  [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                  Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil) else { throw ConnectFailure.signature }

        let audience = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        var rejected: [ConnectFailure] = []
        if claims["iss"] as? String != EndpointPolicy.issuer.absoluteString { rejected.append(.tokenIssuer) }
        // OIDC Core 3.1.3.7: require this client and reject additional untrusted audiences.
        let trustedAudiences = trustedAdditionalAudiences.union([clientID, EndpointPolicy.issuer.absoluteString])
        if !audience.contains(clientID) || !Set(audience).isSubset(of: trustedAudiences) { rejected.append(.tokenAudience) }
        if claims["nonce"] as? String != nonce { rejected.append(.tokenNonce) }
        if (claims["sub"] as? String)?.isEmpty != false { rejected.append(.tokenSubject) }
        let exp = claims["exp"] as? Double ?? 0
        let issued = claims["iat"] as? Double ?? .infinity
        if exp <= now.timeIntervalSince1970 + 30 || issued > now.timeIntervalSince1970 + 60 || issued > exp { rejected.append(.tokenTime) }
        // azp is optional. When supplied it must be a string identifying this exact client.
        // Missing azp must not be treated as a different client just because aud is an array.
        if claims.keys.contains("azp"), claims["azp"] as? String != clientID { rejected.append(.tokenAuthorizedParty) }
        if let nbf = claims["nbf"] as? Double, nbf > now.timeIntervalSince1970 + 60, !rejected.contains(.tokenTime) { rejected.append(.tokenTime) }
        // Only known reason codes leave validation; no claim values or token fragments.
        guard rejected.isEmpty else { throw TokenRejection(reasons: rejected) }
        return Date(timeIntervalSince1970: exp)
    }

    public static func rsaDER(modulus: Data, exponent: Data) -> Data {
        func tlv(_ tag: UInt8, _ bytes: Data) -> Data {
            var length = bytes.count, encoded = Data()
            if length < 128 { encoded.append(UInt8(length)) }
            else {
                var octets: [UInt8] = []
                while length > 0 { octets.insert(UInt8(length & 255), at: 0); length >>= 8 }
                encoded.append(0x80 | UInt8(octets.count)); encoded.append(contentsOf: octets)
            }
            return Data([tag]) + encoded + bytes
        }
        func integer(_ bytes: Data) -> Data {
            var bytes = Data(bytes.drop(while: { $0 == 0 }))
            if bytes.isEmpty { bytes = Data([0]) }
            if bytes.first! & 0x80 != 0 { bytes.insert(0, at: 0) }
            return tlv(0x02, bytes)
        }
        return tlv(0x30, integer(modulus) + integer(exponent))
    }
}
