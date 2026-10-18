import Foundation
import Security
import LocalAuthentication
import ConnectCore

/// Only the native app uses this type. No CLI, socket or WebKit handler can export its values.
final class KeychainVault {
    private let service = "net.iris.connect.local-prototype"

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func save(_ data: Data, account: String, allowInteraction: Bool = true) throws {
        try requireHardenedApp()
        // A file-based Keychain ACL trusts only the creating signed app by default.
        // No -A/all-applications access and no plaintext fallback.
        var access: SecAccess?
        guard SecAccessCreate("Iris Connect — soukromé přihlášení" as CFString, nil, &access) == errSecSuccess,
              let access else { throw ConnectFailure.keychain }
        let existing = interactionQuery(account, allowed: allowInteraction)
        let status = SecItemUpdate(existing as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ConnectFailure.keychain }
        var item = existing
        item[kSecValueData as String] = data
        item[kSecAttrAccess as String] = access
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ConnectFailure.keychain }
    }

    func read(_ account: String, allowInteraction: Bool = true) throws -> Data {
        try requireHardenedApp()
        var q = interactionQuery(account, allowed: allowInteraction)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { throw ConnectFailure.keychain }
        return data
    }

    func contains(_ account: String) -> Bool {
        guard (try? requireHardenedApp()) != nil else { return false }
        var q = query(account)
        q[kSecReturnAttributes as String] = true
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    func delete(_ account: String) throws {
        try requireHardenedApp()
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ConnectFailure.keychain }
    }

    // Both codes are one atomic Keychain item, never a partially updated pair.
    func saveCodes(_ first: String, _ second: String) throws {
        guard !first.isEmpty, !second.isEmpty, first.utf8.count <= 4096, second.utf8.count <= 4096 else { throw ConnectFailure.keychain }
        try save(JSONEncoder().encode(AccessCodes(first: first, second: second)), account: "access-codes")
    }

    func codes(allowInteraction: Bool = true) throws -> AccessCodes {
        try JSONDecoder().decode(AccessCodes.self, from: read("access-codes", allowInteraction: allowInteraction))
    }

    private struct ClientConfiguration: Codable { let id: String; let secret: String }

    func saveClient(_ client: LegacyClient, allowInteraction: Bool = true) throws {
        try save(JSONEncoder().encode(ClientConfiguration(id: client.id, secret: client.secret)),
                 account: "client-configuration", allowInteraction: allowInteraction)
    }

    func client(allowInteraction: Bool = true) throws -> LegacyClient {
        let stored = try JSONDecoder().decode(ClientConfiguration.self,
            from: read("client-configuration", allowInteraction: allowInteraction))
        return try LegacyClient(id: stored.id, secret: stored.secret)
    }

    private func interactionQuery(_ account: String, allowed: Bool) -> [String: Any] {
        var result = query(account)
        if !allowed {
            let context = LAContext(); context.interactionNotAllowed = true
            result[kSecUseAuthenticationContext as String] = context
            result[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        return result
    }

    private func requireHardenedApp() throws {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { throw ConnectFailure.keychain }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { throw ConnectFailure.keychain }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any], let flags = info[kSecCodeInfoFlags as String] as? UInt32,
              flags & 0x10000 != 0 else { throw ConnectFailure.keychain } // CS_RUNTIME
        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
        for name in ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation",
                     "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory"] {
            if entitlements[name] as? Bool == true { throw ConnectFailure.keychain }
        }
    }
}

struct AccessCodes: Codable {
    let first: String
    let second: String
}
