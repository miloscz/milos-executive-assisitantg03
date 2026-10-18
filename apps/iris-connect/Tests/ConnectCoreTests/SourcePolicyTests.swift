import XCTest
@testable import ConnectCore

final class SourcePolicyTests: XCTestCase {
    let base = "https://uuapp.plus4u.net/uu-managementkit-maing02/" + String(repeating: "a", count: 32)
    let oid = String(repeating: "b", count: 24)
    func testExactlyFourManagementKitTypesAndReadOnlyCommands() throws {
        for type in ["document", "meeting", "keyTask", "request"] {
            let target = try SourceTarget(sourceURL: base + "/" + type + "?oid=" + oid)
            XCTAssertEqual(target.entityType, type)
            XCTAssertTrue(target.detailURL().path.hasSuffix("/ai/ecc/document/getMetadata"))
            XCTAssertTrue(try target.contentURL(page: oid).path.hasSuffix("/ai/ecc/panel/getContent"))
            XCTAssertEqual(URLComponents(url: try target.contentURL(page: oid), resolvingAgainstBaseURL: false)?.queryItems?.count, 4)
        }
        for url in [base + "/email?oid=" + oid, base + "/document?oid=" + oid + "&oid=" + oid,
                    base + "/document?oid=" + oid + "&token=synthetic", base + "/document?oid=" + oid + "#fragment",
                    base.replacingOccurrences(of: "https://", with: "https://user@") + "/document?oid=" + oid,
                    base.replacingOccurrences(of: ".net/", with: ".net:443/") + "/document?oid=" + oid,
                    base + "/%64ocument?oid=" + oid, base + "/document/../meeting?oid=" + oid,
                    base.replacingOccurrences(of: "uuapp.plus4u.net", with: "attacker.invalid") + "/document?oid=" + oid] {
            XCTAssertThrowsError(try SourceTarget(sourceURL: url), url)
        }
    }
    func testElementaryAliasesUseOnlyPreviouslyResolvedPageAndBid() throws {
        let target = try SourceTarget(sourceURL: base.replacingOccurrences(of: "uu-managementkit-maing02", with: "uu-elementarymanagement-maing01") + "/meetingDetail?id=" + oid)
        let query = URLComponents(url: try target.contentURL(page: oid, bid: oid), resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.count, 6)
        XCTAssertEqual(query.filter { $0.name == "meetingId" }.first?.value, target.oid)
        XCTAssertThrowsError(try target.contentURL(page: "../bad", bid: oid))
    }
    func testSourceTextDoesNotExecuteComponentsAndDoesNotExportLikelySecrets() {
        let unknown = SourcePolicy.text("<uu5string/><App.Execute command='write'/>Business fact", limit: 100)
        XCTAssertTrue(unknown.incomplete); XCTAssertTrue(unknown.text.contains("Business fact"))
        let secret = SourcePolicy.text("AC1=synthetic-only", limit: 100)
        XCTAssertTrue(secret.incomplete); XCTAssertFalse(secret.text.contains("synthetic-only"))
        let clipped = SourcePolicy.text("123456", limit: 4)
        XCTAssertTrue(clipped.incomplete); XCTAssertEqual(clipped.text, "1234")
    }
    func testLinksAreLimitedToDocumentKeyTaskAndRequestAndCannotSupplyExtraParameters() {
        for type in ["document", "keyTask", "request"] {
            let url = base + "/" + type + "?oid=" + oid
            XCTAssertEqual(SourcePolicy.documentLinks("[source](" + url + ")"), [url])
            XCTAssertEqual(SourcePolicy.documentLinks(url + "&token=synthetic"), [])
        }
        XCTAssertEqual(SourcePolicy.documentLinks(base + "/meeting?oid=" + oid), [])
    }
    func testReadBindingRequiresSameAccountWorkspaceAndBothSignatures() {
        let workspace = "https://uuapp.plus4u.net/uu-myterritory-dwg01/" + String(repeating: "c", count: 32)
        let app = String(repeating: "a", count: 40), helper = String(repeating: "b", count: 40)
        let approval = ReadBindingApproval(appHash: app, helperHash: helper, identity: "123-456", workspace: workspace)
        XCTAssertTrue(approval.matches(appHash: app, helperHash: helper, identity: "123-456", workspace: workspace))
        XCTAssertFalse(approval.matches(appHash: helper, helperHash: helper, identity: "123-456", workspace: workspace))
        XCTAssertFalse(approval.matches(appHash: app, helperHash: app, identity: "123-456", workspace: workspace))
        XCTAssertFalse(approval.matches(appHash: app, helperHash: helper, identity: "999-999", workspace: workspace))
        XCTAssertFalse(approval.matches(appHash: app, helperHash: helper, identity: "123-456", workspace: workspace + "a"))
    }
    func testRequestCannotSupplySourceUrlOrCommand() throws {
        for command in ["diagnostics.sources", "sources.prepare"] {
            XCTAssertNoThrow(try ReadRequest.parse(Data("{\"operation\":\"\(command)\"}".utf8)))
            XCTAssertThrowsError(try ReadRequest.parse(Data("{\"operation\":\"\(command)\",\"url\":\"https://attacker.invalid\"}".utf8)))
        }
    }
    func testOwnSourceEligibilityDoesNotTurnUnknownRecordsIntoTasks() throws {
        let target = try SourceTarget(sourceURL: base + "/request?oid=" + oid)
        func record(_ type: String, _ state: String, cancelled: Bool = false) throws -> NormalizedRecord {
            try NormalizedRecord(["id":"synthetic","name":"Synthetic","tileProps":["activityTypeCode":type,"elementaryActivityStateCode":state,"artifactStateCode":cancelled ? "cancelled":"active"]])
        }
        XCTAssertTrue(SourcePolicy.eligible(try record("decide","initial"),target:target,now:Date()))
        XCTAssertFalse(SourcePolicy.eligible(try record("aiChat","initial"),target:target,now:Date()))
        XCTAssertFalse(SourcePolicy.eligible(try record("decide","solvedActive"),target:target,now:Date()))
        XCTAssertFalse(SourcePolicy.eligible(try record("decide","initial",cancelled:true),target:target,now:Date()))
    }
}
