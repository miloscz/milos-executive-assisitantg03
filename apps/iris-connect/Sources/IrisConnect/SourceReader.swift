import Foundation
import ConnectCore

struct SourcePage: Codable {
    let pageId: String
    let text: String
    let complete: Bool
}
struct SourceMaterial: Codable {
    let recordId: String
    let entityType: String
    let sourceURL: String
    let parentSourceURL: String?
    let fetchedAt: Date
    let pages: [SourcePage]
    let pageCoverage: Int
    let complete: Bool
    let truncated: Bool
    let incompleteReason: String?
    let preparationText: String
    let minutesText: String
}
struct SourceCheck: Codable {
    let type: String
    let verified: Bool
    let pages: Int
    let reason: ReadFailure?
    var stage: SourceStage? = nil
    var shape: [Bool]? = nil
    var issue: SourceIssue? = nil
    var parameterNames: [SourceParameter]? = nil
    var warningShape: [Int]? = nil
}
enum SourceStage: String, Codable { case elementaryDetail, elementaryPage, elementaryPageIdentity, elementarySections, elementaryTarget, elementaryDetailRequest, elementaryPageRequest }
enum SourceIssue: String, Codable { case targetIdentifiers, contentType, jsonObject, serverWarnings }
enum SourceParameter: String, Codable, CaseIterable { case meetingId, id, pageOID = "uuEccPage.oid", pageBID = "uuEccPage.bid", oid, bid }
struct SourceShapeFailure: Error {
    let stage: SourceStage
    let flags: [Bool]
    var issue: SourceIssue? = nil
    var parameterNames: [SourceParameter]? = nil
    var warningShape: [Int]? = nil

    static func onlyEmptyUnsupportedKeys(_ map:[String:Any]) -> Bool {
        !map.isEmpty && map.count<=16 && map.allSatisfy { code,value in
            guard code == "unsupportedKeys" || code.hasSuffix("/unsupportedKeys") else { return false }
            if let list=value as? [Any] { return list.isEmpty }
            if let keys=value as? [String:Any] { return keys.isEmpty }
            return false
        }
    }

    /// Classify only fixed protocol facts. Warning messages, map values and
    /// unknown parameter names are never exported, even when validation fails.
    static func warnings(_ map: [String:Any], stage: SourceStage) -> SourceShapeFailure {
        guard map.count<=16 else { return .init(stage:stage,flags:[true,true,false,false],issue:.serverWarnings) }
        var parameters = Set<SourceParameter>(), onlyUnsupported = !map.isEmpty, knownNames = true
        // Counts only: recognized codes, objects, arrays, standard key maps,
        // compact key maps, unrecognized structures, then six fixed container
        // counts. No arbitrary names or values.
        var shape=Array(repeating:0,count:12)
        func parameter(_ key:String) -> [SourceParameter]? {
            let path=key.hasPrefix("$.") ? String(key.dropFirst(2)) : key
            if path == "uuEccPage" { return [.pageOID,.pageBID] }
            return SourceParameter(rawValue:path).map { [$0] }
        }
        for (code,value) in map {
            guard code == "unsupportedKeys" || code.hasSuffix("/unsupportedKeys") else { onlyUnsupported=false;shape[5]+=1;continue }
            shape[0]+=1
            let names:[String]
            if let list=value as? [String] {
                shape[2]+=1;names=list
            } else if let warning=value as? [String:Any] {
                shape[1]+=1
                let info=warning["paramMap"] as? [String:Any]
                if info != nil { shape[6]+=1 }
                if info?["unsupportedKeyMap"] is [String] || info?["unsupportedKeyList"] is [String] { shape[7]+=1 }
                if warning["unsupportedKeyMap"] is [String:Any] { shape[8]+=1 }
                if warning["unsupportedKeys"] is [String] { shape[9]+=1 }
                if warning["keys"] is [String] { shape[10]+=1 }
                guard warning["type"] == nil || warning["type"] as? String == "warning" else { onlyUnsupported=false;shape[5]+=1;continue }
                if (warning["type"] == nil || warning["type"] as? String == "warning"),
                   let keys=info?["unsupportedKeyMap"] as? [String:Any] {
                    shape[3]+=1;names=Array(keys.keys)
                } else if let list=info?["unsupportedKeyList"] as? [String] ?? info?["unsupportedKeyMap"] as? [String] ?? info?["unsupportedKeys"] as? [String] {
                    names=list
                } else if let keys=warning["unsupportedKeyMap"] as? [String:Any] {
                    shape[4]+=1;names=Array(keys.keys)
                } else if let list=warning["unsupportedKeys"] as? [String] ?? warning["keys"] as? [String] {
                    names=list
                } else if !warning.isEmpty && warning.keys.allSatisfy({ parameter($0) != nil }) {
                    shape[4]+=1;names=Array(warning.keys)
                } else { onlyUnsupported=false;shape[5]+=1;continue }
            } else { if value is String { shape[11]+=1 };onlyUnsupported=false;shape[5]+=1;continue }
            guard !names.isEmpty, names.count<=16 else { onlyUnsupported=false;continue }
            for key in names {
                if let values=parameter(key) { parameters.formUnion(values) } else { knownNames=false }
            }
        }
        return .init(stage:stage,flags:[true,true,onlyUnsupported,knownNames],issue:.serverWarnings,
                     parameterNames:SourceParameter.allCases.filter { parameters.contains($0) },warningShape:shape.map { min($0,16) })
    }
}

/// All content is data. No WebKit, JS, arbitrary URL, attachment or token export.
struct SourceReader {
    let transport: ReadTransport
    let auth: VerifiedSession
    let budget: SourceBudget
    var calibrateAliases = false

    private func object(_ value: [String: Any]) -> [String: Any] { value["data"] as? [String: Any] ?? value }
    func load(_ target: SourceTarget, recordId: String, parent: String? = nil) async throws -> SourceMaterial {
        let detail = object(try await transport.source(target, session: auth, budget: budget))
        if target.elementary { return try await elementary(target, detail: detail, recordId: recordId) }
        guard detail["oid"] as? String == target.oid, detail["entityType"] as? String == target.entityType,
              detail["documentOid"] as? String == target.oid,
              let main = detail["mainPageOid"] as? String, SourcePolicy.hex(main, length: 24),
              let list = detail["pageList"] as? [[String: Any]], !list.isEmpty, list.count <= 1000 else { throw ReadFailure.schemaMismatch }
        var seen = Set<String>(), pages: [String] = [], skipped = false
        for page in list {
            guard let id = page["pageOid"] as? String, SourcePolicy.hex(id, length: 24), seen.insert(id).inserted,
                  page["hidden"] == nil || SourcePolicy.bool(page["hidden"]) != nil else { throw ReadFailure.schemaMismatch }
            if SourcePolicy.bool(page["hidden"]) == true { skipped = true } else { pages.append(id) }
        }
        guard pages.contains(main) else { throw ReadFailure.schemaMismatch }
        pages = [main] + pages.filter { $0 != main }
        skipped = skipped || pages.count > 4
        var result: [SourcePage] = [], total = 0
        for page in pages.prefix(4) {
            let raw = object(try await transport.source(target, page: page, session: auth, budget: budget))
            guard raw["oid"] as? String == target.oid, raw["entityType"] as? String == target.entityType,
                  raw["pageOid"] as? String == page, let mode = raw["contentMode"] as? String, ["full","truncated"].contains(mode),
                  let complete = SourcePolicy.bool(raw["isComplete"]),
                  let sections = raw["sectionList"] as? [[String: Any]], sections.count <= 1000,
                  let scope = raw["scope"] as? String, scope.hasSuffix(".mainPanel") else { throw ReadFailure.schemaMismatch }
            var texts: [String] = [], partial = !complete || mode != "full", ids = Set<String>(), pageChars = 0
            for section in sections {
                guard let id = section["sectionOid"] as? String, SourcePolicy.hex(id, length: 24), ids.insert(id).inserted,
                      section["truncated"] == nil || SourcePolicy.bool(section["truncated"]) != nil else { throw ReadFailure.schemaMismatch }
                guard let text = section["contentUu5String"] as? String else { partial = true; continue }
                let truncated = SourcePolicy.bool(section["truncated"]) ?? false
                let converted = SourcePolicy.text(text, limit: min(20000, max(0, 160000 - total), max(0, 80000 - pageChars)))
                total += converted.text.count; pageChars += converted.text.count; partial = partial || truncated || converted.incomplete
                texts.append(converted.text)
                if total >= 160000 || pageChars >= 80000 { partial = true; break }
            }
            result.append(SourcePage(pageId: page, text: texts.joined(separator: "\n"), complete: !partial))
            if total >= 160000 { skipped = true; break }
        }
        let full = !skipped && result.allSatisfy(\.complete)
        return SourceMaterial(recordId: recordId, entityType: target.entityType, sourceURL: target.sourceURL, parentSourceURL: parent,
            fetchedAt: Date(), pages: result, pageCoverage: result.count, complete: full, truncated: !full,
            incompleteReason: full ? nil : "limitedOrUnsupportedContent", preparationText: result.map(\.text).joined(separator: "\n"), minutesText: "")
    }

    private func elementary(_ target: SourceTarget, detail: [String: Any], recordId: String) async throws -> SourceMaterial {
        // The proven EM adapter binds ownership through the selected meeting,
        // its main page and the fixed request; the response need not echo an oid.
        // If an echo is present, a contradictory identity is always rejected.
        guard detail["id"] == nil || detail["id"] as? String == target.oid,
              let page = detail["uuEccMainPage"] as? String,
              let root = detail["uuEccRoot"] as? [String: Any], let bid = root["bid"] as? String else {
            throw SourceShapeFailure(stage:.elementaryDetail, flags:[detail["id"] != nil,detail["id"] as? String == target.oid,detail["uuEccMainPage"] is String,(detail["uuEccRoot"] as? [String:Any])?["bid"] is String])
        }
        let raw = object(try await transport.source(target, page: page, bid: bid, session: auth, budget: budget, calibrateAliases:calibrateAliases))
        let omissions=Set(await transport.elementaryOmissions(session:auth).map(\.rawValue))
        if SourcePolicy.elementaryMainPageOnly(omissions) {
            let nested=raw["uuEccPage"] as? [String:Any]
            let oid=(raw["oid"] ?? nested?["oid"]) as? String, returnedBID=(raw["bid"] ?? nested?["bid"]) as? String
            guard oid==page,returnedBID==bid,
                  nested?["oid"] == nil || nested?["oid"] as? String==page,
                  nested?["bid"] == nil || nested?["bid"] as? String==bid else {
                throw SourceShapeFailure(stage:.elementaryPageIdentity,flags:[oid != nil,oid==page,returnedBID != nil,returnedBID==bid])
            }
        }
        guard raw["oid"] == nil || raw["oid"] as? String == page,
              let panels = raw["panels"] as? [String: Any], let panel = panels["mainPanel"] as? [String: Any],
              let sections = panel["sectionList"] as? [[String: Any]], sections.count <= 1000 else {
            let panel = (raw["panels"] as? [String:Any])?["mainPanel"] as? [String:Any]
            throw SourceShapeFailure(stage:.elementaryPage, flags:[raw["oid"] != nil,raw["oid"] as? String == page,panel != nil,panel?["sectionList"] is [[String:Any]]])
        }
        var preparation: [String] = [], minutes: [String] = [], region = "before", partial = false
        for wrapper in sections {
            guard let section = wrapper["section"] as? [String: Any], let content = section["content"] as? [Any], content.count <= 1000 else {
                throw SourceShapeFailure(stage:.elementarySections, flags:[wrapper["section"] is [String:Any],(wrapper["section"] as? [String:Any])?["content"] is [Any]])
            }
            for node in content {
                let object = node as? [String:Any] ?? [:]
                let tag = (object["tag"] ?? object["uu5Tag"]) as? String ?? ""
                if tag == "UuElementaryManagement.Meeting.DetailMinutes" { region = "minutes"; continue }
                if tag == "UuElementaryManagement.Meeting.DetailPreparation" { region = "preparation"; continue }
                if tag == "UuElementaryManagement.Meeting.DetailBottom" { region = "after"; continue }
                if tag == "UuElementaryManagement.Meeting.DetailTop" { region = "before"; continue }
                guard ["preparation", "minutes"].contains(region) else { continue }
                let converted = SourcePolicy.nodeText(node)
                partial = partial || converted.incomplete
                if region == "minutes" { minutes.append(converted.text) } else { preparation.append(converted.text) }
            }
        }
        let prep = preparation.joined(separator: "\n"), note = minutes.joined(separator: "\n")
        partial = partial || prep.count > 16000 || note.count > 16000
        return SourceMaterial(recordId: recordId, entityType: "meeting", sourceURL: target.sourceURL, parentSourceURL: nil,
            fetchedAt: Date(), pages: [SourcePage(pageId: page, text: String(prep.prefix(16000)) + "\n" + String(note.prefix(16000)), complete: !partial)],
            pageCoverage: 1, complete: !partial, truncated: partial, incompleteReason: partial ? "limitedOrUnsupportedContent" : nil,
            preparationText: String(prep.prefix(16000)), minutesText: String(note.prefix(16000)))
    }
}
