import Foundation

/// Lock is not sleep or logout. Opt-in is changed only in local native UI while unlocked.
public enum BackgroundLoginPolicy {
    public static func canStart(locked: Bool, enabled: Bool, fromRemote: Bool) -> Bool {
        !locked || (enabled && fromRemote)
    }
    public static func canContinue(locked: Bool, enabled: Bool, remoteAttempt: Bool) -> Bool {
        !locked || (enabled && remoteAttempt)
    }
    public static func mayUseInteractiveKeychain(locked: Bool) -> Bool { !locked }
}
