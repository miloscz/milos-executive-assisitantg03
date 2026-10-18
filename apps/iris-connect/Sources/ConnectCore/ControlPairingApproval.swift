import Foundation

/// Only public code hashes. Never stores a token, a notice or permission to start MFA.
public struct ControlPairingApproval: Codable, Equatable {
    public let version: Int
    public let appHash: String
    public let helperHash: String

    public init(appHash: String, helperHash: String) {
        version = 1; self.appHash = appHash; self.helperHash = helperHash
    }

    public func matches(appHash currentApp: String, helperHash currentHelper: String) -> Bool {
        func valid(_ value: String) -> Bool {
            value.range(of: "\\A[0-9a-f]{40}\\z", options: .regularExpression) != nil
        }
        return version == 1 && valid(appHash) && valid(helperHash)
            && appHash == currentApp && helperHash == currentHelper
    }
}
