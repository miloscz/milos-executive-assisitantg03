import Foundation
import Security
@main struct PolicyTests {
    static func main() {
        precondition(TunnelPolicy.validID("tunnel_0123456789abcdef0123456789abcdef"))
        for value in ["tunnel_x", "https://example.invalid", "tunnel_0123456789abcdef\nextra", "tunnel_0123456789abcdef\"foo"] { precondition(!TunnelPolicy.validID(value)) }
        precondition(TunnelPolicy.validRuntimeKey("sk-SYNTHETIC_ONLY_123456789"))
        for value in ["SYNTHETIC_ACCESS_CODE", "sk-short", "sk-SYNTHETIC_ONLY_123456789\nextra"] { precondition(!TunnelPolicy.validRuntimeKey(value)) }
        precondition(TunnelPolicy.healthURL("http://127.0.0.1:12345\n")?.path == "/readyz")
        for value in ["https://example.invalid", "http://localhost:1234", "http://127.0.0.1:0", "http://127.0.0.1:80?token=synthetic", "http://user:secret@127.0.0.1:1234", "http://127.0.0.1:1234/redirect"] { precondition(TunnelPolicy.healthURL(value) == nil) }
        let config = TunnelPolicy.config(id:"tunnel_0123456789abcdef0123456789abcdef",command:"/bin/bash '/synthetic/path with space/run-stdio.sh'")!
        precondition(config.contains("env:CONTROL_PLANE_API_KEY"))
        precondition(!config.contains("SYNTHETIC_ONLY"))
        precondition(!config.contains("\\/"))
        precondition(TunnelPolicy.quote("/synthetic/\"quoted\"/path") == "\"/synthetic/\\\"quoted\\\"/path\"")
        precondition(TunnelPolicy.config(id:"invalid",command:"fixed") == nil)
        // Known keychain outcomes are classified without exporting errors or their values.
        precondition(TunnelSetupFailure.keychainStatus(errSecItemNotFound, fallback:.keychainRead) == .keyMissing)
        precondition(TunnelSetupFailure.keychainStatus(errSecUserCanceled, fallback:.keychainSave) == .keychainCancelled)
        precondition(TunnelSetupFailure.keychainStatus(errSecInteractionNotAllowed, fallback:.keychainRead) == .keychainInteraction)
        precondition(TunnelSetupFailure.keychainStatus(-123456, fallback:.keychainSave) == .keychainSave)
        // ICU '$' accepts a final newline; credentials and tunnel IDs must match the entire value.
        precondition(!TunnelPolicy.validRuntimeKey("sk-SYNTHETIC_ONLY_123456789\n"))
        precondition(!TunnelPolicy.validID("tunnel_0123456789abcdef0123456789abcdef\n"))
        let synthetic = "sk-SYNTHETIC_ONLY_123456789"
        precondition(TunnelPolicy.normalizedRuntimeKey(" \n\t" + synthetic + "\r\n ") == synthetic)
        precondition(TunnelPolicy.normalizedRuntimeKey(synthetic) == synthetic)
        for value in ["tunnel_0123456789abcdef0123456789abcdef", "sk-SYNTHETIC\n_ONLY_123456789", "sk-SYNTHETIC ONLY_123456789", "", "   "] {
            precondition(TunnelPolicy.normalizedRuntimeKey(value) == nil)
        }
        print("TunnelPolicy: 11 synthetic groups passed; no Keychain access")
    }
}
