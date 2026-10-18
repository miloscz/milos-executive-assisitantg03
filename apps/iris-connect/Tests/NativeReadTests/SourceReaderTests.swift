import XCTest
import Foundation
import ConnectCore
@testable import IrisConnect

private final class SourceProtocol: URLProtocol {
    static var handler: ((URLRequest) -> [String: Any])!
    static var paths: [String] = []
    static var mime = "application/json"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.paths.append(request.url!.path)
        let value = Self.handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":Self.mime])!, cacheStoragePolicy: .notAllowed)
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
    func reader(calibrateAliases:Bool = false) -> SourceReader {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SourceProtocol.self]
        SourceProtocol.paths = []; SourceProtocol.mime="application/json"
        return SourceReader(transport: ReadTransport(configuration: config), auth: VerifiedSession(token: "synthetic-only", expiresAt: Date().addingTimeInterval(1000), identity: "123-456"), budget: SourceBudget(), calibrateAliases:calibrateAliases)
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
    func testElementaryRichTextArraysKeepCurrentPreparationSeparateFromMinutes() async throws {
        let r=reader()
        SourceProtocol.handler = { request in
            if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
            return ["panels":["mainPanel":["sectionList":[
                ["section":["content":[["tag":"UuElementaryManagement.Meeting.DetailPreparation"]]]],
                ["section":["content":[["tag":"UU5.RichText.Block","props":["uu5string":[["tag":"UU5.Bricks.P","children":["Current documented agenda"]]]]]]]],
                ["section":["content":[["tag":"UuElementaryManagement.Meeting.DetailMinutes"]]]],
                ["section":["content":[["tag":"Uu5RichTextBricks.Block","props":["uu5String":["Separate minutes"]]]]]]
            ]]]]
        }
        let value=try await r.load(elementaryTarget(),recordId:"synthetic")
        XCTAssertEqual(value.preparationText,"Current documented agenda")
        XCTAssertEqual(value.minutesText,"Separate minutes");XCTAssertTrue(value.complete)
        XCTAssertEqual(SourceProtocol.paths.count,2)
    }
    func elementaryTarget() throws -> SourceTarget {
        try SourceTarget(sourceURL:"https://uuapp.plus4u.net/uu-elementarymanagement-maing01/"+String(repeating:"a",count:32)+"/meetingDetail?id="+oid)
    }
    func testPilotNarrowsOnlyRejectedAliasesAndNormalReadReusesVerifiedSessionProfile() async throws {
        let r=reader(calibrateAliases:true)
        SourceProtocol.handler = { request in
            if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
            let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            XCTAssertTrue(q.allSatisfy { $0.value==self.oid || $0.value==self.page })
            if q.count==6 { return ["uuAppErrorMap":["unsupportedKeys":["type":"warning","paramMap":["unsupportedKeyMap":["$.meetingId":"private-value","$.uuEccPage":"private-value"]]]]] }
            XCTAssertEqual(Set(q.map(\.name)),["id","oid","bid"])
            return ["panels":["mainPanel":["sectionList":[
                ["section":["content":[["tag":"UuElementaryManagement.Meeting.DetailPreparation"]]]],
                ["section":["content":["Synthetic current agenda"]]]
            ]]]]
        }
        let value=try await r.load(elementaryTarget(),recordId:"synthetic")
        XCTAssertEqual(value.preparationText,"Synthetic current agenda");XCTAssertEqual(SourceProtocol.paths.count,3)
        let normal=SourceReader(transport:r.transport,auth:r.auth,budget:SourceBudget())
        _=try await normal.load(elementaryTarget(),recordId:"synthetic");XCTAssertEqual(SourceProtocol.paths.count,5)
        let other=SourceReader(transport:r.transport,auth:VerifiedSession(token:"other-synthetic",expiresAt:r.auth.expiresAt.addingTimeInterval(1),identity:"other"),budget:SourceBudget())
        do { _=try await other.load(elementaryTarget(),recordId:"synthetic");XCTFail("new session must not inherit calibration") }
        catch let e as SourceShapeFailure { XCTAssertEqual(e.issue,.serverWarnings) }
        XCTAssertEqual(SourceProtocol.paths.count,7)
    }
    func testPilotNeverNarrowsUnknownParametersMissingBindingsOrOtherWarnings() async throws {
        let cases:[(String,String,[String:Any])] = [
            ("unsupportedKeys","warning",["$.unknown":"private"]),
            ("unsupportedKeys","warning",["$.id":"private","$.meetingId":"private"]),
            ("unsupportedKeys","error",["$.meetingId":"private"]),
            ("otherWarning","warning",["$.meetingId":"private"])
        ]
        for (code,type,keys) in cases {
            let r=reader(calibrateAliases:true)
            SourceProtocol.handler = { request in
                if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
                return ["uuAppErrorMap":[code:["type":type,"paramMap":["unsupportedKeyMap":keys]]]]
            }
            do { _=try await r.load(elementaryTarget(),recordId:"synthetic");XCTFail("unsafe narrowing") }
            catch let e as SourceShapeFailure { XCTAssertEqual(e.issue,.serverWarnings) }
            XCTAssertEqual(SourceProtocol.paths.count,2)
        }
    }
    func testPilotDoesNotLoopIfNarrowedRequestStillHasWarnings() async throws {
        let r=reader(calibrateAliases:true)
        SourceProtocol.handler = { request in
            if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
            return ["uuAppErrorMap":["unsupportedKeys":["type":"warning","paramMap":["unsupportedKeyMap":["$.meetingId":"private"]]]]]
        }
        do { _=try await r.load(elementaryTarget(),recordId:"synthetic");XCTFail("must reject second warning") }
        catch let e as SourceShapeFailure { XCTAssertEqual(e.issue,.serverWarnings) }
        XCTAssertEqual(SourceProtocol.paths.count,3)
        let omitted=await r.transport.elementaryOmissions(session:r.auth);XCTAssertTrue(omitted.isEmpty)
    }
    func testCompactUnsupportedKeyListsAndMapsCannotIntroduceUnknownOrUnboundTargets() async throws {
        let valid:[Any] = [["meetingId","uuEccPage"],["$.meetingId":"private-value","$.uuEccPage":"private-value"],
            ["type":"warning","message":"private-value","paramMap":["unsupportedKeyList":["$.meetingId","$.uuEccPage"]]],
            ["paramMap":["unsupportedKeyMap":["meetingId","uuEccPage"]]],
            ["unsupportedKeyMap":["meetingId":"private-value","uuEccPage":"private-value"]],
            ["unsupportedKeys":["meetingId","uuEccPage"]],["keys":["meetingId","uuEccPage"]]]
        for compact in valid {
            let r=reader(calibrateAliases:true)
            SourceProtocol.handler = { request in
                if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
                let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
                if q.count==6 { return ["uuAppErrorMap":["unsupportedKeys":compact]] }
                XCTAssertEqual(Set(q.map(\.name)),["id","oid","bid"])
                return ["panels":["mainPanel":["sectionList":[]]]]
            }
            _=try await r.load(elementaryTarget(),recordId:"synthetic");XCTAssertEqual(SourceProtocol.paths.count,3)
        }
        let invalid:[Any] = [["id","meetingId"],["unknown"],["unknown":"private-value"],["message":"private-value"],
            ["type":"warning","paramMap":["unsupportedKeyList":["$.unknown"]]],
            ["type":"error","paramMap":["unsupportedKeyList":["$.meetingId"]]],
            ["paramMap":["unsupportedKeyList":["$.id","$.meetingId"]]]]
        for compact in invalid {
            let failure=SourceShapeFailure.warnings(["unsupportedKeys":compact],stage:.elementaryPageRequest)
            let keys=Set((failure.parameterNames ?? []).map(\.rawValue))
            XCTAssertFalse(failure.flags == [true,true,true,true] && SourcePolicy.validElementaryOmissions(keys))
        }
    }
    func testMainPageOnlyContractRequiresExactReturnedPageAndBid() async throws {
        for variant in ["valid","wrongPage","missingIdentity"] {
            let r=reader(calibrateAliases:true)
            SourceProtocol.handler = { request in
                if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
                let q=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
                if q.count==6 { return ["uuAppErrorMap":["unsupportedKeys":["meetingId","oid","bid","uuEccPage.oid","uuEccPage.bid"]]] }
                XCTAssertEqual(q.map(\.name),["id"]);XCTAssertEqual(q[0].value,self.oid)
                var result:[String:Any] = ["panels":["mainPanel":["sectionList":[]]]]
                if variant != "missingIdentity" { result["oid"]=variant=="valid" ? self.page : self.oid;result["bid"]=self.oid }
                return result
            }
            do {
                _=try await r.load(elementaryTarget(),recordId:"synthetic")
                XCTAssertEqual(variant,"valid")
            } catch let e as SourceShapeFailure {
                XCTAssertNotEqual(variant,"valid");XCTAssertEqual(e.stage,.elementaryPageIdentity)
            }
        }
    }
    func testOnlyEmptyCompactUnsupportedMetadataIsNotAnActualWarning() async throws {
        let emptyValues:[Any]=[Array<String>(),Dictionary<String,String>()]
        for empty in emptyValues {
            let r=reader()
            SourceProtocol.handler = { request in
                if request.url!.path.hasSuffix("meeting/load") { return ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":self.oid]] }
                return ["uuAppErrorMap":["unsupportedKeys":empty],"panels":["mainPanel":["sectionList":[]]]]
            }
            _=try await r.load(elementaryTarget(),recordId:"synthetic");XCTAssertEqual(SourceProtocol.paths.count,2)
        }
        let invalidMaps:[[String:Any]]=[["otherWarning":[]],["unsupportedKeys":["id"]],["unsupportedKeys":["type":"warning","message":"private"]]]
        for map in invalidMaps {
            XCTAssertFalse(SourceShapeFailure.onlyEmptyUnsupportedKeys(map))
        }
    }
    func testElementaryWarningDiagnosticExportsOnlyKnownParameterEnumsAndDoesNotRetry() async throws {
        let r=reader()
        SourceProtocol.handler = { _ in ["uuAppErrorMap":["app/meeting/load/unsupportedKeys":[
            "message":"synthetic-private-message","paramMap":["unsupportedKeyMap":["$.id":"synthetic-private-value","$.private-unknown-name":"synthetic-private-value"]]]]] }
        do { _ = try await r.load(elementaryTarget(),recordId:"synthetic");XCTFail("warning must remain rejected") }
        catch let e as SourceShapeFailure {
            XCTAssertEqual(e.stage,.elementaryDetailRequest);XCTAssertEqual(e.issue,.serverWarnings)
            XCTAssertEqual(e.flags,[true,true,true,false]);XCTAssertEqual(e.parameterNames,[.id])
            let data=try JSONEncoder().encode(SourceCheck(type:"elementaryMeeting",verified:false,pages:0,reason:.schemaMismatch,stage:e.stage,shape:e.flags,issue:e.issue,parameterNames:e.parameterNames))
            XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("private"))
            XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("technicalNames"))
        }
        XCTAssertEqual(SourceProtocol.paths.count,1)
    }
    func testElementaryTargetDiagnosticDoesNotExportInvalidIdentifierOrTryIt() async throws {
        let r=reader()
        SourceProtocol.handler = { _ in ["id":self.oid,"uuEccMainPage":self.page,"uuEccRoot":["bid":"synthetic-private-bid"]] }
        do { _ = try await r.load(elementaryTarget(),recordId:"synthetic");XCTFail("invalid target") }
        catch let e as SourceShapeFailure { XCTAssertEqual(e.stage,.elementaryTarget);XCTAssertEqual(e.issue,.targetIdentifiers);XCTAssertEqual(e.flags,[true,false,false,false]) }
        XCTAssertEqual(SourceProtocol.paths.count,1)
    }
    func testElementaryResponseContentTypeAndMalformedWarningMapStayRejected() async throws {
        for invalidMime in [true,false] {
            let r=reader();SourceProtocol.mime=invalidMime ? "text/html" : "application/json"
            SourceProtocol.handler = { _ in ["uuAppErrorMap":"synthetic-private-body"] }
            do { _ = try await r.load(elementaryTarget(),recordId:"synthetic");XCTFail("bad response") }
            catch let e as SourceShapeFailure { XCTAssertEqual(e.stage,.elementaryDetailRequest);XCTAssertEqual(e.issue,invalidMime ? .contentType : .serverWarnings) }
            XCTAssertEqual(SourceProtocol.paths.count,1)
        }
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
