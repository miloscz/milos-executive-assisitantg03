import Foundation
import CryptoKit

/// Public pseudonymous reference, never an authorization credential.
/// Only the native app sees the verified identity and confirmed workspace.
public enum ReadBindingReference {
    public static func make(identity: String, workspace: String) throws -> String {
        _ = try ReadPolicy.peopleURL(identity: identity)
        return try make(identityHash: hash(Data(identity.utf8)), workspace: workspace)
    }

    public static func make(identityHash: String, workspace: String) throws -> String {
        guard identityHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw ReadFailure.bindingRequired }
        let canonical = try ReadPolicy.workspace(workspace).absoluteString
        let data = try JSONSerialization.data(withJSONObject: ["iris-self-binding-v1", identityHash, canonical])
        return hash(data)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
