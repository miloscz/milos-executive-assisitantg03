import Foundation
import CryptoKit
import CoreFoundation

/// Public source addresses are resolved inside the native app, never supplied by MCP.
public struct SourceTarget: Equatable {
    public let base: URL
    public let oid: String
    public let entityType: String
    public let elementary: Bool
    public let sourceURL: String

    public init(sourceURL: String) throws {
        guard let c = URLComponents(string: sourceURL), c.scheme == "https", c.host == "uuapp.plus4u.net",
              c.user == nil, c.password == nil, c.port == nil, c.fragment == nil,
              c.percentEncodedPath == c.path else { throw ReadFailure.policyDenied }
        let parts = c.path.split(separator: "/").map(String.init)
        guard parts.count == 3, SourcePolicy.hex(parts[1], length: 32) else { throw ReadFailure.policyDenied }
        elementary = parts[0] == "uu-elementarymanagement-maing01"
        guard elementary ? parts[2] == "meetingDetail" :
                parts[0] == "uu-managementkit-maing02" && ["meeting", "document", "keyTask", "request"].contains(parts[2]),
              let query = c.queryItems, query.count == 1, query[0].name == (elementary ? "id" : "oid"),
              let oid = query[0].value, SourcePolicy.hex(oid, length: 24) else { throw ReadFailure.policyDenied }
        self.oid = oid; entityType = elementary ? "meeting" : parts[2]
        base = URL(string: "https://uuapp.plus4u.net/" + parts[0] + "/" + parts[1])!
        self.sourceURL = sourceURL
    }

    public func detailURL() -> URL {
        url(elementary ? "meeting/load" : "ai/ecc/document/getMetadata", [(elementary ? "id" : "oid", oid)])
    }
    public func contentURL(page: String, bid: String? = nil, omitting: Set<String> = []) throws -> URL {
        guard SourcePolicy.hex(page, length: 24) || (elementary && SourcePolicy.hex(page, length: 32)) else { throw ReadFailure.schemaMismatch }
        if elementary {
            guard let bid, SourcePolicy.hex(bid, length: 24) || SourcePolicy.hex(bid, length: 32) else { throw ReadFailure.schemaMismatch }
            guard omitting.isEmpty || SourcePolicy.validElementaryOmissions(omitting) else { throw ReadFailure.policyDenied }
            return url("meeting/page/load", [("meetingId",oid),("id",oid),("uuEccPage.oid",page),("uuEccPage.bid",bid),("oid",page),("bid",bid)].filter { !omitting.contains($0.0) })
        }
        guard bid == nil, omitting.isEmpty else { throw ReadFailure.policyDenied }
        return url("ai/ecc/panel/getContent", [("oid",oid),("pageOid",page),("maxCharsPerSection","20000"),("maxTotalChars","80000")])
    }
    private func url(_ command: String, _ values: [(String,String)]) -> URL {
        var c = URLComponents(url: base.appendingPathComponent(command), resolvingAgainstBaseURL: false)!
        c.queryItems = values.map { .init(name: $0.0, value: $0.1) }; return c.url!
    }
}

public enum SourcePolicy {
    public static let id = "iris-connect-briefing-sources-v1"
    public static let approvedSHA256 = "85f464e2bf73f5435ef818ec0c98ae65697ea7ab35fc344ef9450d2d16c345e6"
    public static func validElementaryOmissions(_ names:Set<String>) -> Bool {
        let groups:[Set<String>] = [["meetingId","id"],["uuEccPage.oid","oid"],["uuEccPage.bid","bid"]]
        guard !names.isEmpty, names.isSubset(of:groups.reduce(into:Set<String>()) { $0.formUnion($1) }),
              !groups[0].subtracting(names).isEmpty else { return false }
        // A main-page-only endpoint may reject all explicit page aliases. In
        // that case both identities must instead be proved by the response.
        return groups.dropFirst().allSatisfy { !$0.subtracting(names).isEmpty } || elementaryMainPageOnly(names)
    }
    public static func elementaryMainPageOnly(_ names:Set<String>) -> Bool {
        Set(["uuEccPage.oid","oid","uuEccPage.bid","bid"]).isSubset(of:names)
    }
    public static func hex(_ text: String, length: Int) -> Bool {
        text.range(of: "\\A[0-9a-f]{\(length)}\\z", options: .regularExpression) != nil
    }
    public static func approved(_ data: Data) -> Bool {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == approvedSHA256
    }
    public static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    public static func eligible(_ record: NormalizedRecord, target: SourceTarget, now: Date) -> Bool {
        guard !record.cancelled, record.rejected != true else { return false }
        if target.entityType != "meeting" {
            return ["doIt", "decide", "milestone"].contains(record.activityType ?? "")
                && ["initial", "replanned", "reactivated", "attention", "warning"].contains(record.ownElementaryState ?? "")
        }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Prague")!
        let lower = cal.startOfDay(for: now), upper = cal.date(byAdding: .day, value: 14, to: lower)!
        guard let start = try? CalendarInterval.instant(record.startTime), let end = try? CalendarInterval.instant(record.endTime), end >= start else { return false }
        return start < upper && (end > lower || (end == start && start >= lower))
    }
    /// Unknown components are not evaluated. Embedded sources remain missing inputs.
    public static func text(_ value: String, limit: Int) -> (text: String, incomplete: Bool) {
        var text = value
        var unsupported = false
        let safe = Set(["uu5string", "p", "div", "span", "strong", "b", "em", "i", "s", "ul", "ol", "li", "br", "a", "h1", "h2", "h3", "h4", "h5", "h6",
            "uu5.bricks.p", "uu5.bricks.div", "uu5.bricks.span", "uu5.bricks.strong", "uu5.bricks.b", "uu5.bricks.em", "uu5.bricks.i", "uu5.bricks.ul", "uu5.bricks.ol", "uu5.bricks.li", "uu5.bricks.br", "uu5.bricks.link", "uu5.bricks.header", "uu5.bricks.code",
            "uu5.richtext.block", "uu5richtextbricks.block", "uu5bricks.section", "uu5bricks.link", "uu5codekitbricks.markdown", "uu5codekit.markdown", "uu5.codekit.markdown"])
        let tags = (try? NSRegularExpression(pattern: "<(/?)([A-Za-z][A-Za-z0-9_.-]*)\\b[^>]*>"))!
        for match in tags.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let r = Range(match.range(at: 2), in: value) else { continue }
            let tag = String(value[r]).lowercased()
            if !safe.contains(tag) { unsupported = true }
        }
        // Preserve nested rich text stored in string properties before removing markup.
        text = text.replacingOccurrences(of: "\\\"", with: "\"")
        let links = documentLinks(value)
        let property = try! NSRegularExpression(pattern: "(?:uu5string|uu5String|content)=[\"'](<uu5string/>.*?)[\"'](?=[ /])", options: [.dotMatchesLineSeparators])
        for match in property.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            if let whole = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) { text.replaceSubrange(whole, with: String(text[inner])) }
        }
        text = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "[\\x00-\\x08\\x0b-\\x1f]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        // Fail closed for likely secret-bearing source text, without returning the value.
        if text.range(of: "(?i)\\bsk-[a-z0-9_-]{16,}|\\beyJ[a-z0-9_-]{20,}\\.[a-z0-9_-]+\\.|Bearer\\s+\\S+|(?:access[_ -]?token|refresh[_ -]?token|client[_ -]?secret|accessCode[12]|AC[12]|authorization|cookie)\\s*[:=]", options: .regularExpression) != nil {
            return ("[Obsah byl zadržen kvůli možným přístupovým údajům.]", true)
        }
        if !links.isEmpty { text += " Podklady: " + links.joined(separator: " ") }
        return (String(text.prefix(limit)), unsupported || text.count > limit)
    }

    public static func documentLinks(_ text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "https://uuapp\\.plus4u\\.net/uu-managementkit-maing02/[0-9a-f]{32}/(?:document|keyTask|request)\\?oid=[0-9a-f]{24}(?![0-9a-zA-Z_&%/?#=])")
        var found = Set<String>()
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            let url = String(text[range]); return found.insert(url).inserted ? url : nil
        }
    }

    public static func nodeText(_ node: Any, depth: Int = 0) -> (text: String, incomplete: Bool) {
        guard depth < 20 else { return ("",true) }
        if let string = node as? String { return text(string, limit: 16000) }
        guard let object = node as? [String: Any], let tag = (object["tag"] ?? object["uu5Tag"]) as? String else { return ("",true) }
        let props = object["props"] as? [String: Any] ?? [:]
        var result: [String] = [], partial = false
        let allowed = Set(["p", "div", "span", "strong", "b", "em", "i", "s", "ul", "ol", "li", "br", "a",
            "UU5.Bricks.P", "UU5.Bricks.Div", "UU5.Bricks.Span", "UU5.Bricks.Strong", "UU5.Bricks.B", "UU5.Bricks.Em", "UU5.Bricks.I", "UU5.Bricks.Ul", "UU5.Bricks.Ol", "UU5.Bricks.Li", "UU5.Bricks.Br", "UU5.Bricks.Link", "UU5.Bricks.Header", "UU5.Bricks.Code",
            "Uu5Bricks.Section", "Uu5Bricks.Link", "Uu5RichTextBricks.Block", "UU5.RichText.Block", "Uu5Elements.Heading", "Uu5Elements.Paragraph", "Uu5Elements.Text", "Uu5Elements.Link", "Uu5CodeKitBricks.Markdown", "Uu5CodeKit.Markdown", "UU5.CodeKit.Markdown"])
        if !allowed.contains(tag) { partial = true }
        for key in ["header", "uu5String", "uu5string", "content", "value"] {
            if let value = props[key] as? String { let converted = text(value, limit: 16000); result.append(converted.text); partial = partial || converted.incomplete }
        }
        if let children = object["children"] as? [Any] {
            if children.count > 1000 { partial = true }
            for child in children.prefix(1000) {
                let converted = nodeText(child, depth: depth + 1); result.append(converted.text); partial = partial || converted.incomplete
                if result.reduce(0, { $0 + $1.count }) > 16000 { partial = true; break }
            }
        }
        for key in ["href", "src"] { if let value = props[key] as? String { result += documentLinks(value) } }
        let joined = result.joined(separator: " ")
        return (String(joined.prefix(16000)), partial || joined.count > 16000)
    }
}

public struct ReadBindingApproval: Codable, Equatable {
    public let version: Int
    public let appHash: String
    public let helperHash: String
    public let identityHash: String
    public let workspace: String
    public init(appHash: String, helperHash: String, identity: String, workspace: String) {
        version = 1; self.appHash = appHash; self.helperHash = helperHash
        identityHash = Self.digest(identity); self.workspace = workspace
    }
    private static func digest(_ identity: String) -> String { SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined() }
    public func matches(appHash: String, helperHash: String, identity: String, workspace: String) -> Bool {
        version == 1 && ControlPairingApproval(appHash: self.appHash, helperHash: self.helperHash).matches(appHash: appHash, helperHash: helperHash)
            && identityHash == Self.digest(identity) && self.workspace == workspace && (try? ReadPolicy.workspace(workspace)) != nil
    }
}
