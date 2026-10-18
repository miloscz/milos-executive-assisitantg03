import Foundation
import Security

enum TunnelSetupFailure: String, CaseIterable, Error {
    case invalidTunnelID, invalidRuntimeKey, appIntegrity, keyMissing, storedKeyInvalid
    case keychainSave, keychainRead, keychainDenied, keychainCancelled, keychainInteraction, keychainUnavailable, keychainParameters
    case launcherMissing, clientMissing, nodeMissing, configurationWrite, clientLaunch, clientExited

    var message: String {
        switch self {
        case .invalidTunnelID: return "ID tunelu není platné."
        case .invalidRuntimeKey: return "Zadaný údaj nemá očekávaný formát provozního API klíče OpenAI. Zadej klíč pouze do soukromého pole."
        case .appIntegrity: return "Podpis nebo oprávnění aplikace neprošly kontrolou. Klíčenka nebyla zpřístupněna."
        case .keyMissing: return "V klíčence této aplikace ještě není provozní klíč. Zadej ho do soukromého pole."
        case .storedKeyInvalid: return "Uložený údaj nemá očekávaný formát provozního klíče. Zadej celý provozní API klíč OpenAI do soukromého pole."
        case .keychainSave: return "Klíčenka neumožnila uložit provozní klíč."
        case .keychainRead: return "Klíčenka neumožnila přečíst provozní klíč aplikací."
        case .keychainDenied: return "Klíčenka zamítla přístup aplikace. Potvrď případný systémový souhlas přímo na Macu mini."
        case .keychainCancelled: return "Souhlas klíčenky byl zrušen."
        case .keychainInteraction: return "Klíčenka vyžaduje místní odemčení nebo souhlas."
        case .keychainUnavailable: return "Uživatelská klíčenka není dostupná."
        case .keychainParameters: return "Klíčenka odmítla parametry místní operace."
        case .launcherMissing: return "Chybí spustitelný launcher omezeného MCP. Spusť aplikaci z instalační složky projektu."
        case .clientMissing: return "Chybí spustitelný přibalený tunnel-client."
        case .nodeMissing: return "Chybí Node v podporovaném instalačním umístění."
        case .configurationWrite: return "Nepodařilo se uložit místní nastavení tunelu bez tajných hodnot."
        case .clientLaunch: return "macOS nespustil přibalený tunnel-client."
        case .clientExited: return "Klient tunelu skončil. Zkontroluj ID tunelu a oprávnění provozního klíče."
        }
    }

    static func keychainStatus(_ code: OSStatus, fallback: Self) -> Self {
        switch code {
        case errSecItemNotFound: return .keyMissing
        case errSecAuthFailed: return .keychainDenied
        case errSecUserCanceled: return .keychainCancelled
        case errSecInteractionNotAllowed: return .keychainInteraction
        case errSecNotAvailable: return .keychainUnavailable
        case errSecParam: return .keychainParameters
        default: return fallback
        }
    }
}

enum TunnelPolicy {
    // The native caller alone receives the normalized value; never publish or log it.
    static func normalizedRuntimeKey(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return validRuntimeKey(normalized) ? normalized : nil
    }
    static func validRuntimeKey(_ value: String) -> Bool {
        value.range(of: "\\Ask-[A-Za-z0-9_-]{16,4090}\\z", options: .regularExpression) != nil
    }
    static func validID(_ value: String) -> Bool {
        value.range(of: "\\Atunnel_[A-Za-z0-9_-]{16,128}\\z", options: .regularExpression) != nil
    }
    static func healthURL(_ text: String) -> URL? {
        guard text.utf8.count <= 256, var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme == "http", c.host == "127.0.0.1", let port = c.port, port > 0, port <= 65535,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/" else { return nil }
        c.path = "/readyz"; return c.url
    }
    static func quote(_ value: String) -> String {
        // The client's YAML parser rejects JSON's optional escaped slash (\/).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(data: try! encoder.encode(value), encoding: .utf8)!
    }
    static func config(id: String, command: String) -> String? {
        guard validID(id), !command.contains("\n") else { return nil }
        return """
        config_version: 1
        control_plane:
          base_url: "https://api.openai.com"
          tunnel_id: \(quote(id))
          api_key: "env:CONTROL_PLANE_API_KEY"
        health:
          listen_addr: "127.0.0.1:0"
        admin_ui:
          open_browser: false
        log:
          level: error
          format: json
        mcp:
          commands:
            - channel: main
              command: \(quote(command))
        """
    }
}
