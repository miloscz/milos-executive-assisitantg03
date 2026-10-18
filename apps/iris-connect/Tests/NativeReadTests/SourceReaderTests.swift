import XCTest
import Foundation
import ConnectCore
@testable import IrisConnect

private final class SourceProtocol: URLProtocol {
    static var handler: ((URLRequest) -> [String: Any])!
    static var paths: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.paths.append(request.url!.path)
        let value = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: value))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SourceReaderTests: XCTestCase {
    let oid = String(repeating: "b", count: 24), page = String(repeating: "c", count: 24)
    func target(_ type: String = "document") throws -> SourceTarget {
        try SourceTarget(sourceURL: "https://uuapp.plus4u.net/uu-managementkit-maing02/" + String(repeating: "a", count: 32) + "/" + type + "?oid=" + oid)
    }
    func reader() -> SourceReader {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SourceProtocol.self]
        SourceProtocol.paths = []
        return SourceReader(transport: ReadTransport(configuration: config), auth: VerifiedSession(token: "synthetic-only", expiresAt: Date().addingTimeInterval(1000), identity: "123-456"), budget: SourceBudget())
    }
    func metadata(_ type: String) -> [String: Any] {
        ["oid":oid,"documentOid":oid,"entityType":type,"mainPageOid":page,"pageList":[["pageOid":page,"hidden":false]]]
    }
    func content(_ type: String) -> [String: Any] {
        ["oid":oid,"entityType":type,"pageOid":page,"scope":"mainPage.mainPanel","contentMode":"full","isComplete":true,
         "sectionList":[["sectionOid":String(repeating:"d",count:24),"contentUu5String":"<uu5string/><UU5.Bricks.P>Verified synthetic fact</UU5.Bricks.P>","truncated":false]]]
    }
    func testReadsAllFourTypesWithMatchingIdentityAndPageOnly() async throws {
        for type in ["document", "meeting", "keyTask", "request"] {
            let r = reader()
            SourceProtocol.handler = { request in
                XCTAssertEqual(request.httpMethod,"GET")
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL:false)!.queryItems!
                XCTAssertEqual(query.first(where: {$0.name=="oid"})?.value,self.oid)
                if request.url!.path.hasSuffix("getMetadata") { return self.metadata(type) }
                XCTAssertEqual(query.first(where: {$0.name=="pageOid"})?.value,self.page)
                XCTAssertEqual(query.first(where: {$0.name=="maxTotalChars"})?.value,"80000")
                return self.content(type)
            }
            let value = try await r.load(target(type), recordId:"synthetic-record")
            XCTAssertTrue(value.complete); XCTAssertEqual(value.pages.count,1)
            XCTAssertTrue(value.preparationText.contains("Verified synthetic fact"))
            XCTAssertEqual(SourceProtocol.paths.count,2)
        }
    }
    func testWrongEntityOrPageCannotExportContentOrTryAnotherCommand() async throws {
        let r = reader()
        SourceProtocol.handler = { _ in self.metadata("request") }
        do { _ = try await r.load(target(), recordId:"synthetic"); XCTFail("wrong entity must fail") }
        catch { XCTAssertEqual(error as? ReadFailure,.schemaMismatch) }
        XCTAssertEqual(SourceProtocol.paths.count,1)
        let second = reader()
        SourceProtocol.handler = { request in
            if request.url!.path.hasSuffix("getMetadata") { return self.metadata("document") }
            var v = self.content("document");v["pageOid"] = String(repeating:"e",count:24);return v
        }
        do { _ = try await second.load(target(), recordId:"synthetic"); XCTFail("wrong page must fail") }
        catch { XCTAssertEqual(error as? ReadFailure,.schemaMismatch) }
        XCTAssertEqual(SourceProtocol.paths.count,2)
    }
    func testTruncationUnsupportedComponentsAndHiddenPagesAreExplicitlyIncomplete() async throws {
        let r = reader()
        SourceProtocol.handler = { request in
            if request.url!.path.hasSuffix("getMetadata") {
                var v = self.metadata("document");v["pageList"] = [["pageOid":self.page,"hidden":false],["pageOid":String(repeating:"e",count:24),"hidden":true]];return v
            }
            var v = self.content("document");v["isComplete"] = false;v["contentMode"] = "truncated";return v
        }
        let value = try await r.load(target(), recordId:"synthetic")
        XCTAssertFalse(value.complete);XCTAssertTrue(value.truncated);XCTAssertNotNil(value.incompleteReason)
        XCTAssertEqual(SourceProtocol.paths.count,2)
    }
    func testElementaryRegionMarkersDoNotMixPreparationAndMinutes() async throws {
        let r = reader()
        SourceProtocol.handler = { request in
            if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
            return ["panels":["mainPanel":["sectionList":[
                ["section":["content":[["tag":"UuElementaryManagement.Meeting.DetailPreparation"]]]],
                ["section":["content":[["uu5Tag":"UU5.Bricks.P","children":["PREPARATION"]]]]],
                ["section":["content":[["tag":"UuElementaryManagement.Meeting.DetailMinutes"]]]],
                ["section":["content":[["uu5Tag":"Uu5CodeKitBricks.Markdown","props":["value":"MINUTES"]]]]]
            ]]]]
        }
        let em = try SourceTarget(sourceURL:"https://uuapp.plus4u.net/uu-elementarymanagement-maing01/" + String(repeating:"a",count:32) + "/meetingDetail?id=" + oid)
        let value = try await r.load(em,recordId:"synthetic")
        XCTAssertTrue(value.complete);XCTAssertEqual(value.preparationText,"PREPARATION");XCTAssertEqual(value.minutesText,"MINUTES")
    }
    func testContradictoryElementaryEchoIsRejectedWithoutLeakingBody() async throws {
        let r=reader()
        SourceProtocol.handler = { request in
            if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
            return ["oid":self.oid,"panels":["mainPanel":["sectionList":[]]],"private":"synthetic-private-body"]
        }
        let em=try SourceTarget(sourceURL:"https://uuapp.plus4u.net/uu-elementarymanagement-maing01/"+String(repeating:"a",count:32)+"/meetingDetail?id="+oid)
        do { _ = try await r.load(em,recordId:"synthetic");XCTFail("contradictory echo") }
        catch let error as SourceShapeFailure { XCTAssertEqual(error.stage,.elementaryPage);XCTAssertEqual(error.flags,[true,false,true,true]) }
    }
    func testSharedAttemptAndByteBudgetIsNotResetBetweenSources() async throws {
        let budget = SourceBudget()
        for _ in 0..<120 { try await budget.attempt() }
        do { try await budget.attempt();XCTFail("attempt cap") } catch { XCTAssertEqual(error as? ReadFailure,.rateLimited) }
        try await budget.consume(134_217_728)
        do { try await budget.consume(1);XCTFail("byte cap") } catch { XCTAssertEqual(error as? ReadFailure,.responseTooLarge) }
    }
    func testPageCharacterCapIsAppliedLocallyEvenIfServerIgnoresLimit() async throws {
        let r = reader()
        SourceProtocol.handler = { request in
            if request.url!.path.hasSuffix("getMetadata") { return self.metadata("document") }
            var v = self.content("document")
            v["sectionList"] = (0..<6).map { i in ["sectionOid":String(format:"%024x",i),"contentUu5String":String(repeating:"x",count:20000),"truncated":false] as [String:Any] }
            return v
        }
        let value = try await r.load(target(),recordId:"synthetic")
        XCTAssertFalse(value.complete);XCTAssertTrue(value.truncated)
        XCTAssertLessThanOrEqual(value.pages[0].text.filter { $0 != "\n" }.count,80000)
    }
}
