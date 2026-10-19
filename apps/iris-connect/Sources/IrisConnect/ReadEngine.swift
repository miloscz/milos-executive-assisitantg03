import Foundation
import ConnectCore

struct AgendaResult: Codable {
    let operation: String
    let fetchedAt: Date
    let scope: String
    let dateWindow: DateWindow?
    let complete: Bool
    let consistency: String
    let counts: Counts
    let stale: Bool
    let incompleteReason: ReadFailure?
    let contractVerified: Bool
    let records: [NormalizedRecord]
    let bindingRef: String?
    struct Counts: Codable { let records: Int; let pages: Int }
}

struct ReadCheck: Codable {
    let operation: String
    let readSucceeded: Bool
    let records: Int
    let pages: Int
    let complete: Bool
    let contractVerified: Bool
    let reason: ReadFailure?
}

struct CalendarBoundaryEvidence: Codable {
    let verified: Bool
    let checkedAt: Date
    let timezone: String
    let wireFormat: String
    let paddedWindowMatches: Bool
    let activeCoverageMatches: Bool
    let adjacentWindowsMatch: Bool
    let boundaryFilterMatches: Bool
    let legacyDateOnlyMatchesUTCMidnight: Bool
    let matchingDateModels: [String]
    let dstChecked: Bool
    let dstMatches: Bool
    let dstDayHours: Int
    let dstRecords: Int
    let dayBlockSamples: Int
    let multiDaySamples: Int
    let scope: String
}

@MainActor
final class ReadEngine: ObservableObject {
    @Published private(set) var status = "Čtecí rozhraní čeká na přihlášení."
    @Published private(set) var candidate: URL?
    @Published private(set) var paired = false
    @Published private(set) var working = false
    @Published private(set) var checks: [ReadCheck] = []
    @Published private(set) var sourceChecks: [SourceCheck] = []
    @Published private(set) var remembersReadBinding = false
    var canConfigure: () -> Bool = { false }
    private let readApprovalKey = "readBindingApprovalV1"
    private var sourceTypesVerified = Set<String>()
    private var sourcesWorking = false
    private var auth: VerifiedSession?
    private var bound: URL?
    private var generation = UUID()
    private let transport = ReadTransport()
    private var server: ReadServer?
    private var cache: [String: AgendaResult] = [:]
    private var flights: [String: Task<AgendaResult, Never>] = [:]
    private var calendarVerified = false
    // Snapshot only public prior binding metadata, not an old login or consent.
    // New code still requires its own local pairing before exporting anything.
    private let previousBindingRef: String? = {
        guard let data = UserDefaults.standard.data(forKey: "readBindingApprovalV1"),
              let old = try? JSONDecoder().decode(ReadBindingApproval.self, from: data), old.version == 1 else { return nil }
        return try? ReadBindingReference.make(identityHash: old.identityHash, workspace: old.workspace)
    }()

    private func bindingReference() throws -> String {
        guard paired, let bound, let auth, auth.expiresAt > Date(), specificationValid else { throw ReadFailure.bindingRequired }
        return try ReadBindingReference.make(identity: auth.identity, workspace: bound.absoluteString)
    }
    private var checkingBoundaries = false
    private var specificationValid: Bool {
        guard let url = Bundle.main.url(forResource: "iris-connect-read-v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return false }
        return ReadPolicy.verifyApprovedSpecification(data)
    }

    func install(_ session: VerifiedSession) {
        disconnect(); auth = session
        status = "Relace je připravená. Najdi a potvrď vlastní pracovní prostor."
        let epoch = generation
        guard let data = UserDefaults.standard.data(forKey: readApprovalKey),
              let approval = try? JSONDecoder().decode(ReadBindingApproval.self, from: data) else { return }
        working = true
        Task {
            defer { if epoch == generation { working = false } }
            do {
                let current = try codeHashes()
                guard approval.matches(appHash: current.app, helperHash: current.helper, identity: session.identity, workspace: approval.workspace) else { throw ReadFailure.pairingRequired }
                let object = try await transport.person(identity: session.identity, session: session)
                guard epoch == generation else { return }
                let workspace = try ReadPolicy.personWorkspace(object, identity: session.identity)
                guard approval.matches(appHash: current.app, helperHash: current.helper, identity: session.identity, workspace: workspace.absoluteString) else { throw ReadFailure.bindingRequired }
                candidate = workspace; try startReadServer(); remembersReadBinding = true
                status = "Čtecí párování stejného účtu a prostoru je obnovené. Kalendář a zdroje se znovu ověří."
            } catch {
                guard epoch == generation else { return }
                remembersReadBinding = false
                status = "Automatická obnova čtení není dostupná. Potvrď vlastní prostor a klienta místně."
            }
            writeReceipt()
        }
    }

    func disconnect() {
        generation = UUID(); auth = nil; bound = nil; candidate = nil; paired = false; working = false
        for task in flights.values { task.cancel() }; flights.removeAll(); cache.removeAll(); checks = []
        server?.stop(); server = nil; calendarVerified = false
        sourceTypesVerified.removeAll(); sourceChecks = []; remembersReadBinding = false
        status = "Čtecí rozhraní čeká na přihlášení."
        writeReceipt()
    }

    func findWorkspace() {
        guard canConfigure(), !working, specificationValid, let auth, auth.expiresAt > Date() else { status = "Nejdřív se přihlas v odemčené aplikaci."; return }
        working = true; status = "Ověřuji vlastní prostor přes people/findPerson."
        let epoch = generation
        Task {
            defer { if epoch == generation { working = false } }
            do {
                let object = try await transport.person(identity: auth.identity, session: auth)
                guard epoch == generation else { return }
                candidate = try ReadPolicy.personWorkspace(object, identity: auth.identity)
                status = "Vlastní identita odpovídá. Potvrď prostor a místního klienta níže."
            } catch {
                guard epoch == generation else { return }
                status = "Nalezení prostoru: \((error as? ReadFailure ?? .schemaMismatch).rawValue). Žádný jiný cíl nebyl zkoušen."
            }
            writeReceipt()
        }
    }

    func pairAndBind() {
        guard canConfigure(), specificationValid, candidate != nil, let auth, auth.expiresAt > Date(), !working else { return }
        do {
            try startReadServer()
            status = "Vlastní prostor a přibalený klient IrisRead jsou spárované pro tento běh."
            writeReceipt()
        } catch { status = "Párování: \((error as? ReadFailure ?? .pairingRequired).rawValue)." }
    }

    private func startReadServer() throws {
            guard specificationValid, let candidate else { throw ReadFailure.bindingRequired }
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/IrisRead")
            let hash = try LocalIPC.codeHash(LocalIPC.staticCode(helper))
            let next = ReadServer(approvedHelperHash: hash) { [weak self] data in
                guard let self else { return Data("{\"ok\":false,\"error\":\"pairingRequired\"}".utf8) }
                return await self.handle(data)
            }
            try next.start()
            bound = candidate; paired = true; server = next
    }

    private func codeHashes() throws -> (app: String, helper: String) {
        (try LocalIPC.codeHash(LocalIPC.staticCode(Bundle.main.bundleURL)),
         try LocalIPC.codeHash(LocalIPC.staticCode(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/IrisRead"))))
    }
    func setRememberReadBinding(_ enabled: Bool) {
        guard canConfigure(), !working else { return }
        if !enabled { UserDefaults.standard.removeObject(forKey: readApprovalKey); remembersReadBinding = false; return }
        guard paired, let bound, let auth, auth.expiresAt > Date() else { return }
        do {
            let hashes = try codeHashes()
            let approval = ReadBindingApproval(appHash: hashes.app, helperHash: hashes.helper, identity: auth.identity, workspace: bound.absoluteString)
            UserDefaults.standard.set(try JSONEncoder().encode(approval), forKey: readApprovalKey)
            remembersReadBinding = true
        } catch { status = "Uložení čtecího souhlasu se nezdařilo." }
    }

    func verifyReads() {
        guard !working, paired else { return }
        working = true
        Task { _ = await pilot(); working = false }
    }

    private func pilot() async -> [ReadCheck] {
        let epoch = generation
        var results: [ReadCheck] = []
        for operation in ReadOperation.allCases {
            guard epoch == generation else { return [] }
            let result = await read(ReadRequest(operation: operation.rawValue, fresh: true))
            results.append(ReadCheck(operation: operation.rawValue,
                readSucceeded: result.incompleteReason == nil || result.incompleteReason == .contractPending,
                records: result.records.count, pages: result.counts.pages, complete: result.complete,
                contractVerified: result.contractVerified, reason: result.incompleteReason))
        }
        guard epoch == generation else { return [] }
        checks = results
        status = results.allSatisfy(\.readSucceeded)
            ? "Čtení všech tří seznamů proběhlo. Neověřené časové kontrakty zůstávají označené."
            : "Ověření čtení skončilo; výsledky jednotlivých operací jsou níže."
        writeReceipt()
        return results
    }

    private func read(_ request: ReadRequest) async -> AgendaResult {
        let operation = ReadOperation(rawValue: request.operation)!
        let window = operation == .active ? nil : try? DateWindow(request: request)
        let key = request.operation + (window?.dateFrom ?? "") + (window?.dateTo ?? "")
        if request.fresh != true, let saved = cache[key], saved.complete,
           Date().timeIntervalSince(saved.fetchedAt) < (operation == .calendar ? 60 : 120) { return saved }
        if let running = flights[key] { return await running.value }
        let epoch = generation
        let task = Task { await self.fetch(operation, window: window, epoch: epoch) }
        flights[key] = task
        let result = await task.value
        if epoch == generation {
            flights.removeValue(forKey: key)
            if result.complete { cache[key] = result }
        }
        return result
    }

    private func fetch(_ operation: ReadOperation, window: DateWindow?, epoch: UUID) async -> AgendaResult {
        var accumulated = PageAccumulator(); var byteCount = 0
        var failure: ReadFailure?
        var contractVerified = false
        let bounds = operation == .calendar && calendarVerified ? window.flatMap { try? CalendarInterval(window: $0) } : nil
        do {
            guard paired, let bound else { throw ReadFailure.bindingRequired }
            guard let auth, auth.expiresAt > Date() else { throw ReadFailure.loginRequired }
            guard specificationValid else { throw ReadFailure.policyDenied }
            let deadline = Date().addingTimeInterval(180)
            for page in 0..<50 {
                guard epoch == generation else { throw ReadFailure.cancelled }
                try Task.checkCancellation()
                let (object, bytes) = try await transport.page(base: bound, operation: operation, window: window,
                    index: page, session: auth, deadline: deadline, calendarBounds: bounds)
                guard epoch == generation else { throw ReadFailure.cancelled }
                byteCount += bytes
                guard byteCount <= 52_428_800 else { throw ReadFailure.responseTooLarge }
                let parsed = try RecordPage(object, operation: operation, page: page)
                if try accumulated.append(parsed) {
                    // Active has no date predicates. Diary boundary/overlap and final date semantics
                    // cannot be proven merely from an HTTP 200 and remain diagnostic only.
                    contractVerified = operation == .active || (operation == .calendar && calendarVerified)
                    if !contractVerified { failure = .contractPending }
                    break
                }
            }
        } catch { failure = error as? ReadFailure ?? .transport }
        var records = accumulated.records
        if let bounds, contractVerified {
            do { records = try records.filter { try bounds.includes($0) } }
            catch { failure = .schemaMismatch; contractVerified = false; records = [] }
        }
        return AgendaResult(operation: operation.rawValue, fetchedAt: Date(), scope: "self", dateWindow: window,
            complete: failure == nil, consistency: "bestEffort", counts: .init(records: records.count, pages: accumulated.pages),
            stale: false, incompleteReason: failure, contractVerified: contractVerified, records: records,
            bindingRef: try? bindingReference())
    }

    /// Fixed read-only calibration. Only counts/booleans leave this diagnostic;
    /// normal calendar records remain gated until all required comparisons pass.
    private func verifyCalendarBoundaries() async throws -> CalendarBoundaryEvidence {
        guard !checkingBoundaries else { throw ReadFailure.rateLimited }
        guard paired, let bound, let auth, auth.expiresAt > Date(), specificationValid else { throw ReadFailure.loginRequired }
        checkingBoundaries = true; defer { checkingBoundaries = false }
        let epoch = generation, deadline = Date().addingTimeInterval(180)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Prague")!
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let today = cal.startOfDay(for: Date())
        func day(_ offset: Int) -> String { f.string(from: cal.date(byAdding: .day, value: offset, to: today)!) }
        func window(_ from: Int, _ through: Int) throws -> DateWindow {
            try DateWindow(request: .init(operation: "calendar.list", dateFrom: day(from), dateTo: day(through)))
        }
        let wideWindow = try window(-7, 30), wideBounds = try CalendarInterval(window: wideWindow)
        func raw(_ bounds: CalendarInterval?, window: DateWindow) async throws -> [NormalizedRecord] {
            var pages = PageAccumulator(); var bytes = 0
            for index in 0..<50 {
                guard epoch == generation, Date() < deadline else { throw ReadFailure.cancelled }
                let (object, count) = try await transport.page(base: bound, operation: .calendar, window: window,
                    index: index, session: auth, deadline: deadline, calendarBounds: bounds)
                bytes += count; guard bytes <= 52_428_800 else { throw ReadFailure.responseTooLarge }
                if try pages.append(RecordPage(object, operation: .calendar, page: index)) {
                    // The server sees enclosing date-only bounds; the client owns
                    // the exact half-open interval, including DST and point events.
                    if let bounds { return try pages.records.filter { try bounds.includes($0) } }
                    return pages.records
                }
            }
            throw ReadFailure.recordLimit
        }
        let wide = try await raw(wideBounds, window: wideWindow)
        // Every result must have an explicit offset, a non-reversed interval and a documented diary mode.
        for record in wide {
            guard ["timeblock", "dayblock"].contains(record.showInDiary?.lowercased() ?? "") else { throw ReadFailure.schemaMismatch }
            _ = try wideBounds.includes(record)
        }
        // Empty weekend days must not prevent a weekday refresh. Pick a populated
        // calibration day from the same already authorized [-7,+30] sample.
        let active = await read(.init(operation: ReadOperation.active.rawValue, fresh: true))
        guard active.complete else { throw active.incompleteReason ?? ReadFailure.transport }
        let blockingActive = active.records.filter { ["timeblock", "dayblock"].contains($0.showInDiary?.lowercased() ?? "") }
        let calibrationOffset = try CalendarInterval.calibrationOffset(wide:wide, active:blockingActive, now:today)
        let tomorrow = try window(calibrationOffset, calibrationOffset), tomorrowBounds = try CalendarInterval(window: tomorrow)
        let exact = try await raw(tomorrowBounds, window: tomorrow)
        let explicit = Set(exact.map(\.id)) == (try tomorrowBounds.ids(wide))
        let activeExpected = try tomorrowBounds.ids(blockingActive)
        let activeCoverage = activeExpected.isSubset(of: Set(exact.map(\.id)))
        let next = try window(calibrationOffset+1, calibrationOffset+1), nextBounds = try CalendarInterval(window: next)
        let nextRows = try await raw(nextBounds, window: next)
        let joinedWindow = try window(calibrationOffset, calibrationOffset+1), joinedBounds = try CalendarInterval(window: joinedWindow)
        let joined = try await raw(joinedBounds, window: joinedWindow)
        let expectedNext = try nextBounds.ids(wide)
        let adjacent = Set(exact.map(\.id)).union(nextRows.map(\.id)) == Set(joined.map(\.id))
            && Set(nextRows.map(\.id)) == expectedNext
        guard let edgeRecord = try wide.first(where: {
            let start = try CalendarInterval.instant($0.startTime), end = try CalendarInterval.instant($0.endTime)
            return $0.showInDiary?.lowercased() == "timeblock" && end > start && start > wideBounds.lower.addingTimeInterval(3600) && start < wideBounds.upper.addingTimeInterval(-3600)
        }) else { throw ReadFailure.contractPending }
        let edge = try CalendarInterval.instant(edgeRecord.startTime)
        var edgeMatches = true
        for bounds in [try CalendarInterval(lower: edge.addingTimeInterval(-1800), upper: edge),
                       try CalendarInterval(lower: edge, upper: edge.addingTimeInterval(1800))] {
            let rows = try await raw(bounds, window: wideWindow)
            let expected = try bounds.ids(wide)
            edgeMatches = edgeMatches && Set(rows.map(\.id)) == expected
        }
        // Establish the UTC-midnight interpretation of the supported date() wire
        // format against the wider sample before enabling its enclosing adapter.
        let legacyWindow = try window(calibrationOffset, calibrationOffset+1), legacy = try await raw(nil, window: legacyWindow)
        let legacyBounds = try CalendarInterval(lower: CalendarInterval.instant(day(calibrationOffset) + "T00:00:00Z"), upper: CalendarInterval.instant(day(calibrationOffset+1) + "T00:00:00Z"))
        let legacyUTC = Set(legacy.map(\.id)) == (try legacyBounds.ids(wide, documentedPredicate: true))
        let models = try CalendarInterval.dateModels(window: legacyWindow)
        let matchingModels = try models.filter { try $0.bounds.ids(wide, documentedPredicate: true) == Set(legacy.map(\.id)) }.map(\.name)
        var dstChecked = false, dstMatches = true, dstHours = 0, dstRecords = 0
        if let transition = cal.timeZone.nextDaylightSavingTimeTransition(after: today), transition < wideBounds.upper {
            let date = f.string(from: transition)
            let w = try DateWindow(request: .init(operation: "calendar.list", dateFrom: date, dateTo: date))
            let bounds = try CalendarInterval(window: w), rows = try await raw(bounds, window: w)
            dstChecked = true; dstHours = Int(bounds.upper.timeIntervalSince(bounds.lower) / 3600); dstRecords = rows.count
            dstMatches = Set(rows.map(\.id)) == (try bounds.ids(wide))
        }
        guard epoch == generation else { throw ReadFailure.cancelled }
        let multiDay = try wide.filter { try CalendarInterval.instant($0.endTime).timeIntervalSince(CalendarInterval.instant($0.startTime)) >= 86400 }.count
        let verified = !exact.isEmpty && !activeExpected.isEmpty && explicit && activeCoverage && adjacent && edgeMatches && !matchingModels.isEmpty && dstMatches
        calendarVerified = verified; cache = cache.filter { !$0.key.hasPrefix(ReadOperation.calendar.rawValue) }
        return CalendarBoundaryEvidence(verified: verified, checkedAt: Date(), timezone: "Europe/Prague", wireFormat: "dateOnlyUTCEnclosure", paddedWindowMatches: explicit,
            activeCoverageMatches: activeCoverage, adjacentWindowsMatch: adjacent, boundaryFilterMatches: edgeMatches,
            legacyDateOnlyMatchesUTCMidnight: legacyUTC, matchingDateModels: matchingModels,
            dstChecked: dstChecked, dstMatches: dstMatches, dstDayHours: dstHours, dstRecords: dstRecords,
            dayBlockSamples: wide.filter { $0.showInDiary?.lowercased() == "dayblock" }.count, multiDaySamples: multiDay,
            scope: "self; documented DAO predicate; live sample; bestEffort; approval iris-connect-read-v1")
    }

    private func handle(_ data: Data) async -> Data {
        do {
            let request = try ReadRequest.parse(data)
            guard paired, auth?.expiresAt ?? .distantPast > Date() else { throw ReadFailure.loginRequired }
            if request.operation == "status" {
                let reference = try bindingReference()
                return encode(Status(ok: true, policy: ReadPolicy.id, paired: true, loginRequired: false, checks: checks,
                    bindingRef: reference, previousBindingRef: previousBindingRef == reference ? reference : nil))
            }
            if request.operation == "diagnostics.verifyReads" { return encode(await pilot()) }
            if request.operation == "diagnostics.calendarBoundaries" { return encode(try await verifyCalendarBoundaries()) }
            if request.operation == "diagnostics.sources" { return encode(try await sourceBatch(pilot: true)) }
            if request.operation == "sources.prepare" { return encode(try await sourceBatch(pilot: false)) }
            let result = await read(request)
            // Unverified contracts never export personal records to a normal client.
            guard result.contractVerified else { throw result.incompleteReason ?? ReadFailure.contractPending }
            return encode(result)
        } catch { return encode(ErrorResult(ok: false, error: error as? ReadFailure ?? .schemaMismatch)) }
    }

    private struct SourceBatch: Encodable {
        let ok: Bool
        let policy: String
        let fetchedAt: Date
        let complete: Bool
        let checks: [SourceCheck]
        let materials: [SourceMaterial]
        let bindingRef: String?
    }

    private func sourceBatch(pilot: Bool) async throws -> SourceBatch {
        guard !sourcesWorking else { throw ReadFailure.rateLimited }
        guard specificationValid, let file = Bundle.main.url(forResource: SourcePolicy.id, withExtension: "json"),
              let data = try? Data(contentsOf: file), SourcePolicy.approved(data) else { throw ReadFailure.policyDenied }
        guard paired, let auth, auth.expiresAt > Date() else { throw ReadFailure.loginRequired }
        sourcesWorking = true; defer { sourcesWorking = false }
        let epoch = generation, snapshotTime = Date()
        let active = await read(.init(operation: ReadOperation.active.rawValue, fresh: true))
        guard epoch == generation, active.complete else { throw active.incompleteReason ?? ReadFailure.cancelled }
        // No inferred calendar availability or final records may seed a source read.
        guard calendarVerified else { throw ReadFailure.contractPending }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Prague")!
        let f = DateFormatter(); f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let calendar = await read(.init(operation: ReadOperation.calendar.rawValue,
            dateFrom: f.string(from: snapshotTime), dateTo: f.string(from: cal.date(byAdding: .day, value: 13, to: snapshotTime)!), fresh: true))
        guard epoch == generation, calendar.complete else { throw calendar.incompleteReason ?? ReadFailure.cancelled }
        var candidates: [(NormalizedRecord, SourceTarget)] = [], seen = Set<String>()
        for record in (active.records + calendar.records).sorted(by: { ($0.startTime ?? "9999") < ($1.startTime ?? "9999") }) {
            guard let url = record.sourceURL, let target = try? SourceTarget(sourceURL: url),
                  SourcePolicy.eligible(record, target: target, now: snapshotTime), seen.insert(url).inserted else { continue }
            // Non-meeting sources must originate in the complete active list.
            if target.entityType != "meeting", !active.records.contains(where: { $0.id == record.id }) { continue }
            candidates.append((record,target))
        }
        // Give near decisions precedence over historical backlog; retained items
        // outside the bounded batch remain explicitly incomplete.
        candidates.sort { left, right in
            func rank(_ value: (NormalizedRecord, SourceTarget)) -> (Int, String, String) {
                let (record, target) = value
                if target.entityType == "meeting" { return (0, record.startTime ?? "9999", record.id) }
                let due = (try? CalendarInterval.instant(record.endTime ?? record.startTime)) ?? .distantPast
                let recent = due >= snapshotTime.addingTimeInterval(-7 * 86400)
                return (recent ? 1 : 2, record.activityType == "decide" ? "0" : "1", record.endTime ?? record.startTime ?? "9999")
            }
            return rank(left) < rank(right)
        }
        let budget = SourceBudget(), reader = SourceReader(transport: transport, auth: auth, budget: budget, calibrateAliases:pilot)
        var materials: [SourceMaterial] = [], checks: [SourceCheck] = [], tested = Set<String>()
        var meetings = 0, documents = 0, textCount = 0, complete = true, visited = Set<String>()
        func type(_ target: SourceTarget) -> String { target.elementary ? "elementaryMeeting" : "managementKit." + target.entityType }
        for (record, target) in candidates {
            guard epoch == generation else { throw ReadFailure.cancelled }
            if visited.contains(target.sourceURL) { continue }
            guard Date().timeIntervalSince(snapshotTime) < 300 else { complete = false; break }
            let key = type(target)
            if pilot && tested.contains(key) { continue }
            if target.entityType == "meeting" { if meetings >= 16 { complete = false; continue }; meetings += 1 }
            else { if documents >= 8 { complete = false; continue }; documents += 1 }
            guard pilot || sourceTypesVerified.contains(key) else { complete = false; continue }
            tested.insert(key); visited.insert(target.sourceURL)
            do {
                let material = try await reader.load(target, recordId: record.id)
                guard epoch == generation else { throw ReadFailure.cancelled }
                checks.append(SourceCheck(type: key, verified: true, pages: material.pageCoverage, reason: nil,
                    parameterNames:target.elementary ? await transport.elementaryOmissions(session:auth) : nil))
                if pilot { sourceTypesVerified.insert(key); continue }
                textCount += material.preparationText.count + material.minutesText.count
                if textCount > 600000 { complete = false; break }
                materials.append(material); complete = complete && material.complete
                // Exactly one hop from roots; secondary material is never recursed.
                for link in SourcePolicy.documentLinks(material.preparationText + "\n" + material.minutesText) {
                    if !visited.insert(link).inserted { continue }
                    guard documents < 8, Date().timeIntervalSince(snapshotTime) < 300,
                          let secondary = try? SourceTarget(sourceURL: link), sourceTypesVerified.contains(type(secondary)) else { complete = false; continue }
                    documents += 1
                    do {
                        let child = try await reader.load(secondary, recordId: record.id, parent: target.sourceURL)
                        guard epoch == generation else { throw ReadFailure.cancelled }
                        textCount += child.preparationText.count
                        if textCount > 600000 { complete = false; break }
                        materials.append(child); complete = complete && child.complete
                    } catch { complete = false }
                }
            } catch {
                guard epoch == generation else { throw ReadFailure.cancelled }
                complete = false
                let shape = error as? SourceShapeFailure
                checks.append(SourceCheck(type: key, verified: false, pages: 0, reason: error as? ReadFailure ?? .schemaMismatch,stage:shape?.stage,shape:shape?.flags,issue:shape?.issue,parameterNames:shape?.parameterNames,warningShape:shape?.warningShape))
            }
        }
        if pilot {
            for key in ["elementaryMeeting", "managementKit.meeting", "managementKit.document", "managementKit.keyTask", "managementKit.request"] where !tested.contains(key) {
                checks.append(SourceCheck(type: key, verified: false, pages: 0, reason: .contractPending))
            }
            sourceChecks = checks; complete = checks.allSatisfy(\.verified)
        }
        guard epoch == generation else { throw ReadFailure.cancelled }
        return SourceBatch(ok: true, policy: SourcePolicy.id, fetchedAt: Date(), complete: complete, checks: checks,
            materials: pilot ? [] : materials, bindingRef: pilot ? nil : try bindingReference())
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data("{\"ok\":false,\"error\":\"schemaMismatch\"}".utf8)
    }

    private func writeReceipt() {
        let receipt = Receipt(ok: true, policy: ReadPolicy.id, paired: paired,
                             loginRequired: auth?.expiresAt ?? .distantPast <= Date(), checks: checks)
        try? FileManager.default.createDirectory(at: LocalIPC.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = LocalIPC.directory.appendingPathComponent("read-verification.json")
        try? encode(receipt).write(to: path, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    private struct ErrorResult: Encodable { let ok: Bool; let error: ReadFailure }
    private struct Receipt: Encodable {
        let ok: Bool; let policy: String; let paired: Bool; let loginRequired: Bool; let checks: [ReadCheck]
    }
    private struct Status: Encodable {
        let ok: Bool; let policy: String; let paired: Bool; let loginRequired: Bool; let checks: [ReadCheck]
        let bindingRef: String; let previousBindingRef: String?
    }
}
