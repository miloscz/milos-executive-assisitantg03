import XCTest
@testable import ConnectCore

final class ControlPairingApprovalTests: XCTestCase {
    private let app = String(repeating: "a", count: 40)
    private let helper = String(repeating: "b", count: 40)

    func testRestoresOnlyTheSameAppAndHelper() throws {
        let saved = ControlPairingApproval(appHash: app, helperHash: helper)
        let restored = try JSONDecoder().decode(ControlPairingApproval.self, from: JSONEncoder().encode(saved))
        XCTAssertTrue(restored.matches(appHash: app, helperHash: helper))
        XCTAssertFalse(restored.matches(appHash: helper, helperHash: helper))
        XCTAssertFalse(restored.matches(appHash: app, helperHash: app))
    }

    func testUnknownVersionAndMalformedHashesFailClosed() throws {
        for (version, appHash, helperHash) in [(2, app, helper), (1, "", helper), (1, app, helper + "\n"), (1, "SYNTHETIC_PRIVATE_CANARY", helper)] {
            let data = try JSONSerialization.data(withJSONObject: ["version":version, "appHash":appHash, "helperHash":helperHash])
            let saved = try JSONDecoder().decode(ControlPairingApproval.self, from: data)
            XCTAssertFalse(saved.matches(appHash: appHash, helperHash: helperHash))
        }
    }

    func testApprovalCannotRestoreAnOldStartPermit() throws {
        var state = AuthControlState()
        let now = Date(timeIntervalSince1970: 1000)
        state.prepare(sessionValid: false, now: now)
        let notice = try XCTUnwrap(state.noticeID)
        try state.markNotice(notice, now: now)
        state.recover()
        XCTAssertNil(state.noticeID)
        XCTAssertThrowsError(try state.start(notice: notice, request: UUID(), now: now))
        XCTAssertNotEqual(state.phase, .authenticating)
    }
}
