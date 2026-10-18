import XCTest
@testable import ConnectCore
final class BackgroundLoginPolicyTests: XCTestCase {
    func testLockedStartRequiresOptInAndRemoteOrigin() {
        // A local login must never become a background attempt merely by locking the Mac.
        XCTAssertTrue(BackgroundLoginPolicy.canStart(locked:false,enabled:false,fromRemote:false))
        XCTAssertFalse(BackgroundLoginPolicy.canStart(locked:true,enabled:false,fromRemote:true))
        XCTAssertFalse(BackgroundLoginPolicy.canStart(locked:true,enabled:true,fromRemote:false))
        XCTAssertTrue(BackgroundLoginPolicy.canStart(locked:true,enabled:true,fromRemote:true))
    }
    func testLockNeverAllowsInteractiveKeychainAndOptOutStopsRemoteAttempt() {
        XCTAssertFalse(BackgroundLoginPolicy.mayUseInteractiveKeychain(locked:true))
        XCTAssertTrue(BackgroundLoginPolicy.mayUseInteractiveKeychain(locked:false))
        XCTAssertTrue(BackgroundLoginPolicy.canContinue(locked:true,enabled:true,remoteAttempt:true))
        XCTAssertFalse(BackgroundLoginPolicy.canContinue(locked:true,enabled:false,remoteAttempt:true))
        XCTAssertFalse(BackgroundLoginPolicy.canContinue(locked:true,enabled:true,remoteAttempt:false))
    }
}
