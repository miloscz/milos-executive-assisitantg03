import Foundation
import CryptoKit

public enum ConnectFailure: String, Error, LocalizedError {
    case configuration, transport, response, cancelled, expired, callback, token, signature, policy, keychain
    case tokenAlgorithm, tokenIssuer, tokenAudience, tokenNonce, tokenSubject, tokenTime, tokenAuthorizedParty
    case loginMethod

    public var errorDescription: String? {
        switch self {
        case .configuration: return "Chybí kompatibilní konfigurace přihlášení původní Iris."
        case .transport: return "Spojení s +4U není dostupné. Zkus přihlášení znovu."
        case .response: return "+4U vrátilo neočekávanou odpověď. Přihlášení nebylo ověřeno."
        case .cancelled: return "Přihlášení bylo zrušeno."
        case .expired: return "Pokus vypršel. Přihlášení můžeš spustit znovu."
        case .callback: return "Návrat přihlášení neodpovídá aktivnímu pokusu."
        case .token: return "Přijatý token neprošel kontrolou identity relace."
        case .tokenAlgorithm: return "Token používá nepodporovaný podpisový algoritmus."
        case .tokenIssuer: return "Vydavatel tokenu neodpovídá očekávanému +4U issueru."
        case .tokenAudience: return "Příjemce tokenu neodpovídá očekávanému klientovi."
        case .tokenNonce: return "Token neobsahuje očekávané nonce tohoto přihlašovacího pokusu."
        case .tokenSubject: return "Token neobsahuje očekávaný identifikátor přihlášeného účtu."
        case .tokenTime: return "Časové údaje tokenu neprošly kontrolou platnosti."
        case .tokenAuthorizedParty: return "Token není vydaný pro očekávaného autorizovaného klienta."
        case .signature: return "Podpis přihlašovacího tokenu nebyl ověřen."
        case .policy: return "Tato operace nebo cílová adresa není povolená."
        case .keychain: return "Klíčenka operaci nepovolila. Údaje nejsou uloženy do souboru."
        case .loginMethod: return "Oficiální formulář Plus4U Access se nepodařilo bezpečně otevřít. Přihlašovací stránka se mohla změnit."
        }
    }
}

public struct LegacyClient {
    public static let defaultPath = "/Users/milosvodrazka/Personal/milos_executive_assistant/mcp-servers/iris-dwg-mcp/src/oidc.js"
    public let id: String
    public let secret: String
    public let issuer: URL
    public let scope = "openid offline_access https:// http://localhost"
    public static let requestedCallAudiences: Set<String> = ["https://", "http://localhost"]

    public init(id: String, secret: String) throws {
        guard !id.isEmpty, !secret.isEmpty, id.utf8.count <= 4096, secret.utf8.count <= 4096,
              !id.contains(where: { $0.isNewline }), !secret.contains(where: { $0.isNewline }) else { throw ConnectFailure.configuration }
        self.id = id; self.secret = secret; issuer = EndpointPolicy.issuer
    }

    /// Reads only source constants, never legacy credentials.json or .env.
    public init(source: String) throws {
        func value(_ name: String) throws -> String {
            let pattern = "const\\s+" + name + "\\s*=\\s*[\"']([^\"'\\r\\n]+)[\"']\\s*;"
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
                  let range = Range(match.range(at: 1), in: source) else { throw ConnectFailure.configuration }
            return String(source[range])
        }
        guard source.utf8.count <= 524288, let url = URL(string: try value("OIDC_BASE")),
              url.absoluteString == EndpointPolicy.issuer.absoluteString else { throw ConnectFailure.configuration }
        try self.init(id: value("CLIENT_ID"), secret: value("CLIENT_SECRET"))
    }

    public static func load() throws -> LegacyClient {
        guard let source = try? String(contentsOfFile: defaultPath, encoding: .utf8) else { throw ConnectFailure.configuration }
        return try LegacyClient(source: source)
    }
}

public enum EndpointPolicy {
    public static let issuer = URL(string: "https://uuidentity.plus4u.net/uu-oidc-maing02/bb977a99f4cc4c37a2afce3fd599d0a7/oidc")!
    public static let loginPath = "/uu-identitymanagement-maing01/a9b105aff2744771be4daa8361954677/login"

    public static func allows(_ url: URL, path: String) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.scheme == "https" && c.host == "uuidentity.plus4u.net" && (c.port == nil || c.port == 443)
            && c.user == nil && c.password == nil && c.path == path && c.query == nil && c.fragment == nil
    }

    public static func endpoint(_ suffix: String) -> URL { issuer.appendingPathComponent(suffix) }

    public static func allowsMainNavigation(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return c.scheme == "https" && c.host == "uuidentity.plus4u.net" && (c.port == nil || c.port == 443)
            && c.user == nil && c.password == nil
    }

    /// Credential insertion is narrower than navigation and never runs on MFA or registration pages.
    public static func allowsCredentialInsertion(_ url: URL) -> Bool {
        allowsMainNavigation(url) && url.path == loginPath
    }
}

public struct LoginAttempt {
    public let id = UUID()
    public let state: String
    public let nonce: String
    public let verifier: String
    public let callbackURL: URL
    public let expiresAt: Date

    public init(now: Date = Date()) {
        func random() -> String { Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL }
        state = random(); nonce = random(); verifier = random()
        // WKNavigationDelegate intercepts this URI. No local TCP listener is exposed.
        callbackURL = URL(string: "http://localhost:\(Int.random(in: 49152...65535))/")!
        expiresAt = now.addingTimeInterval(300)
    }

    public func authorizationURL(client: LegacyClient) throws -> URL {
        var c = URLComponents(url: EndpointPolicy.endpoint("auth"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: client.id), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: callbackURL.absoluteString), .init(name: "scope", value: client.scope),
            .init(name: "state", value: state), .init(name: "nonce", value: nonce),
            .init(name: "code_challenge", value: Data(SHA256.hash(data: Data(verifier.utf8))).base64URL),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "prompt", value: "login")
        ]
        guard let url = c.url else { throw ConnectFailure.configuration }; return url
    }

    public func matchesCallback(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.user == nil, c.password == nil else { return false }
        return c.scheme == callbackURL.scheme && c.host == callbackURL.host && c.port == callbackURL.port
            && c.path == callbackURL.path && c.fragment == nil
    }

    public func authorizationCode(from url: URL, now: Date = Date()) throws -> String {
        guard now < expiresAt else { throw ConnectFailure.expired }
        guard matchesCallback(url), let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw ConnectFailure.callback }
        let items = c.queryItems ?? []
        guard items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.utf8.count <= 8192,
              !items.contains(where: { ["error", "uuAppErrorMap"].contains($0.name) }) else { throw ConnectFailure.callback }
        return code
    }
}

public extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        guard base64URL.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        let padded = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: padded + String(repeating: "=", count: (4 - padded.count % 4) % 4))
    }
}
