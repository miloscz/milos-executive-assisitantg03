import XCTest
@testable import ConnectCore

final class AuthControlTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testRejectsUnknownKeysAndCredentialInputs() throws {
        for input in [#"{"operation":"status","token":"synthetic"}"#,
                      #"{"operation":"start","url":"https://example.invalid"}"#,
                      #"{"operation":"export"}"#,
                      #"{"operation":"prepare","accessCode1":"synthetic"}"#,
                      #"{"operation":"status","noticeID":null}"#] {
            XCTAssertThrowsError(try AuthControlRequest.parse(Data(input.utf8)))
        }
        XCTAssertNoThrow(try AuthControlRequest.parse(Data(#"{"operation":"status"}"#.utf8)))
    }
    func testStartRequiresNoticeAndFreshDirectCommand() throws {
        let notice = UUID(), request = UUID()
        for flag in ["false", "null", "1", #""true""#] {
            let json = "{\"operation\":\"start\",\"noticeID\":\"\(notice)\",\"requestID\":\"\(request)\",\"directUserCommand\":\(flag)}"
            XCTAssertThrowsError(try AuthControlRequest.parse(Data(json.utf8)))
        }
        let valid = AuthControlRequest(operation: "start", noticeID: notice, requestID: request, directUserCommand: true)
        XCTAssertNoThrow(try AuthControlRequest.parse(JSONEncoder().encode(valid)))
        var state = AuthControlState()
        state.prepare(sessionValid: false, now: now)
        XCTAssertThrowsError(try state.start(notice: state.noticeID!, request: request, now: now))
        try state.markNotice(state.noticeID!, now: now)
        XCTAssertTrue(try state.start(notice: state.noticeID!, request: request, now: now))
        XCTAssertFalse(try state.start(notice: notice, request: request, now: now))
        XCTAssertThrowsError(try state.start(notice: notice, request: UUID(), now: now))
    }
    func testExpiryAndRepeatedAckCannotExtendPermit() throws {
        var state = AuthControlState()
        state.prepare(sessionValid: false, now: now)
        let notice = state.noticeID!
        try state.markNotice(notice, now: now)
        try state.markNotice(notice, now: now.addingTimeInterval(599))
        XCTAssertThrowsError(try state.start(notice: notice, request: UUID(), now: now.addingTimeInterval(600)))
        state.prepare(sessionValid: false, now: now.addingTimeInterval(601))
        XCTAssertNotEqual(state.noticeID, notice)
        XCTAssertEqual(state.phase, .awaitingNotice)
    }
    func testPollingDoesNotRepeatNoticeOrLaunchLogin() throws {
        var state = AuthControlState()
        state.prepare(sessionValid: false, now: now)
        let event = state.eventID, notice = state.noticeID!
        for _ in 0..<100 { state.prepare(sessionValid: false, now: now) }
        XCTAssertEqual(event, state.eventID)
        XCTAssertEqual(notice, state.noticeID)
        XCTAssertEqual(state.phase, .awaitingNotice)
        try state.markNotice(notice, now: now)
        let request = UUID()
        _ = try state.start(notice: notice, request: request, now: now)
        state.prepare(sessionValid: false, now: now)
        XCTAssertEqual(state.phase, .authenticating)
        state.finish(.failed)
        XCTAssertFalse(try state.start(notice: notice, request: request, now: now))
        XCTAssertEqual(state.phase, .failed)
    }
    func testRestartInvalidatesPermitAndNeverRetries() throws {
        var state = AuthControlState()
        state.prepare(sessionValid: false, now: now)
        let notice = state.noticeID!, request = UUID()
        try state.markNotice(notice, now: now)
        var restored = try JSONDecoder().decode(AuthControlState.self, from: JSONEncoder().encode(state))
        restored.recover()
        XCTAssertNil(restored.noticeID)
        XCTAssertThrowsError(try restored.start(notice: notice, request: request, now: now))
        _ = try state.start(notice: notice, request: request, now: now)
        state.recover()
        XCTAssertEqual(state.phase, .interrupted)
        XCTAssertFalse(try state.start(notice: notice, request: request, now: now))
        XCTAssertEqual(state.phase, .interrupted)
    }
    func testSuccessLockAndIdleDoNotGenerateNewChallenges() throws {
        var state = AuthControlState()
        state.prepare(sessionValid: true, now: now)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.workPending)
        state.prepare(sessionValid: false, now: now)
        let notice = state.noticeID!
        try state.markNotice(notice, now: now)
        state.invalidateNotice()
        XCTAssertThrowsError(try state.start(notice: notice, request: UUID(), now: now))
        state.finish(.authenticated)
        XCTAssertFalse(state.workPending)
        XCTAssertNil(state.noticeID)
    }
    func testFreshAttemptsAreRateLimitedAcrossPersistence() throws {
        var state = AuthControlState()
        state.prepare(sessionValid: false, now: now)
        let first = state.noticeID!
        try state.markNotice(first, now: now)
        _ = try state.start(notice: first, request: UUID(), now: now)
        state.finish(.failed)
        state = try JSONDecoder().decode(AuthControlState.self, from: JSONEncoder().encode(state))
        state.recover()
        state.prepare(sessionValid: false, now: now.addingTimeInterval(30))
        let second = state.noticeID!
        try state.markNotice(second, now: now.addingTimeInterval(30))
        XCTAssertThrowsError(try state.start(notice: second, request: UUID(), now: now.addingTimeInterval(30))) {
            XCTAssertEqual($0 as? AuthControlFailure, .rateLimited)
        }
        XCTAssertTrue(try state.start(notice: second, request: UUID(), now: now.addingTimeInterval(60)))
    }

}
