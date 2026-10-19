import XCTest
@testable import ConnectCore

final class ReadBindingReferenceTests: XCTestCase {
    func testStableWithoutSessionOrBuildAndMatchesPriorPublicApproval() throws {
        let workspace = "https://uuapp.plus4u.net/uu-myterritory-dwg01/" + String(repeating: "a", count: 32)
        let first = try ReadBindingReference.make(identity: "123-456", workspace: workspace)
        let approval = ReadBindingApproval(appHash: "old-app", helperHash: "old-helper", identity: "123-456", workspace: workspace)
        XCTAssertEqual(first, try ReadBindingReference.make(identityHash: approval.identityHash, workspace: workspace))
        XCTAssertEqual(first, try ReadBindingReference.make(identity: "123-456", workspace: workspace))
        XCTAssertEqual(first.count, 64)
        XCTAssertFalse(first.contains("123-456"))
        XCTAssertNotEqual(first, try ReadBindingReference.make(identity: "123-457", workspace: workspace))
        XCTAssertNotEqual(first, try ReadBindingReference.make(identity: "123-456", workspace: workspace.replacingOccurrences(of: "aaaa", with: "bbbb")))
    }
    func testInvalidIdentityWorkspaceAndDigestRejected() {
        XCTAssertThrowsError(try ReadBindingReference.make(identity: "untrusted", workspace: "https://example.invalid"))
        XCTAssertThrowsError(try ReadBindingReference.make(identityHash: "not-a-hash", workspace: "https://example.invalid"))
        XCTAssertThrowsError(try ReadBindingReference.make(identityHash: String(repeating: "a", count: 64), workspace: "https://example.invalid"))
    }
}
