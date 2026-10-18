import Foundation
import ConnectCore

final class OIDCService: NSObject, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward a bearer header or client secret through redirects.
    }

    private func request(_ suffix: String, method: String = "GET", body: [String: String]? = nil, bearer: String? = nil) async throws -> Data {
        let allowed = [".well-known/openid-configuration", "grantToken", "listKeys", "getIdentity"]
        guard allowed.contains(suffix), (suffix == "grantToken" ? method == "POST" : method == "GET") else { throw ConnectFailure.policy }
        let url = EndpointPolicy.endpoint(suffix)
        guard EndpointPolicy.allows(url, path: url.path) else { throw ConnectFailure.policy }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw ConnectFailure.transport }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 1_048_576 else { throw ConnectFailure.response }
        return data
    }

    func verifyDiscovery() async throws {
        let data = try await request(".well-known/openid-configuration")
        guard let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              metadata["issuer"] as? String == EndpointPolicy.issuer.absoluteString,
              metadata["authorization_endpoint"] as? String == EndpointPolicy.endpoint("auth").absoluteString,
              metadata["token_endpoint"] as? String == EndpointPolicy.endpoint("grantToken").absoluteString,
              metadata["jwks_uri"] as? String == EndpointPolicy.endpoint("listKeys").absoluteString,
              (metadata["code_challenge_methods_supported"] as? [String])?.contains("S256") == true else { throw ConnectFailure.configuration }
    }

    func finish(code: String, attempt: LoginAttempt, client: LegacyClient) async throws -> VerifiedSession {
        guard Date() < attempt.expiresAt else { throw ConnectFailure.expired }
        let data = try await request("grantToken", method: "POST", body: [
            "grant_type": "authorization_code", "code": code, "client_id": client.id, "client_secret": client.secret,
            "redirect_uri": attempt.callbackURL.absoluteString, "scope": client.scope, "code_verifier": attempt.verifier
        ])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let token = object["id_token"] as? String else { throw ConnectFailure.response }
        let jwks = try await request("listKeys")
        let expiry = try TokenValidation.validate(token, jwks: jwks, clientID: client.id, nonce: attempt.nonce,
            trustedAdditionalAudiences: LegacyClient.requestedCallAudiences)
        // Same bearer convention as the existing Iris, tested against a fixed read endpoint.
        let probe = try await request("getIdentity", bearer: token)
        guard let identity = try JSONSerialization.jsonObject(with: probe) as? [String: Any], !identity.isEmpty else { throw ConnectFailure.response }
        if let map = identity["uuAppErrorMap"] as? [String: [String: Any]], map.values.contains(where: { $0["type"] as? String == "error" }) { throw ConnectFailure.response }
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3, let payload = Data(base64URL: parts[1]),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw ConnectFailure.tokenSubject }
        let ownIdentity = (claims["uuidentity"] as? String) ?? (claims["uuIdentity"] as? String) ?? (claims["sub"] as? String)
        guard let ownIdentity, ownIdentity.range(of: "^[0-9]+-[0-9]+(?:-[0-9]+)?$", options: .regularExpression) != nil else { throw ConnectFailure.tokenSubject }
        return VerifiedSession(token: token, expiresAt: expiry, identity: ownIdentity)
    }
}

struct VerifiedSession: Codable {
    let token: String
    let expiresAt: Date
    let identity: String
}
