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

@MainActor
final class ReadEngine: ObservableObject {
    @Published private(set) var status = "Čtecí rozhraní čeká na přihlášení."
    @Published private(set) var candidate: URL?
    @Published private(set) var paired = false
    @Published private(set) var working = false
    @Published private(set) var checks: [ReadCheck] = []
    private var auth: VerifiedSession?
    private var bound: URL?
    private var generation = UUID()
    private let transport = ReadTransport()
    private var server: ReadServer?
    private var cache: [String: AgendaResult] = [:]
    private var flights: [String: Task<AgendaResult, Never>] = [:]
    private var specificationValid: Bool {
        guard let url = Bundle.main.url(forResource: "iris-connect-read-v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return false }
        return ReadPolicy.verifyApprovedSpecification(data)
    }

    func install(_ session: VerifiedSession) {
        disconnect(); auth = session
        status = "Relace je připravená. Najdi a potvrď vlastní pracovní prostor."
    }

    func disconnect() {
        generation = UUID(); auth = nil; bound = nil; candidate = nil; paired = false; working = false
        for task in flights.values { task.cancel() }; flights.removeAll(); cache.removeAll(); checks = []
        server?.stop(); server = nil
        status = "Čtecí rozhraní čeká na přihlášení."
        writeReceipt()
    }

    func findWorkspace() {
        guard !working, specificationValid, let auth, auth.expiresAt > Date() else { status = "Nejdřív se přihlas v aplikaci."; return }
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
        guard specificationValid, let candidate, let auth, auth.expiresAt > Date(), !working else { return }
        do {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/IrisRead")
            let hash = try LocalIPC.codeHash(LocalIPC.staticCode(helper))
            let next = ReadServer(approvedHelperHash: hash) { [weak self] data in
                guard let self else { return Data("{\"ok\":false,\"error\":\"pairingRequired\"}".utf8) }
                return await self.handle(data)
            }
            try next.start()
            bound = candidate; paired = true; server = next
            status = "Vlastní prostor a přibalený klient IrisRead jsou spárované pro tento běh."
            writeReceipt()
        } catch { status = "Párování: \((error as? ReadFailure ?? .pairingRequired).rawValue)." }
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
        do {
            guard paired, let bound else { throw ReadFailure.bindingRequired }
            guard let auth, auth.expiresAt > Date() else { throw ReadFailure.loginRequired }
            guard specificationValid else { throw ReadFailure.policyDenied }
            let deadline = Date().addingTimeInterval(180)
            for page in 0..<50 {
                guard epoch == generation else { throw ReadFailure.cancelled }
                try Task.checkCancellation()
                let (object, bytes) = try await transport.page(base: bound, operation: operation, window: window,
                    index: page, session: auth, deadline: deadline)
                guard epoch == generation else { throw ReadFailure.cancelled }
                byteCount += bytes
                guard byteCount <= 52_428_800 else { throw ReadFailure.responseTooLarge }
                let parsed = try RecordPage(object, operation: operation, page: page)
                if try accumulated.append(parsed) {
                    // Active has no date predicates. Diary boundary/overlap and final date semantics
                    // cannot be proven merely from an HTTP 200 and remain diagnostic only.
                    contractVerified = operation == .active
                    if !contractVerified { failure = .contractPending }
                    break
                }
            }
        } catch { failure = error as? ReadFailure ?? .transport }
        return AgendaResult(operation: operation.rawValue, fetchedAt: Date(), scope: "self", dateWindow: window,
            complete: failure == nil, consistency: "bestEffort", counts: .init(records: accumulated.records.count, pages: accumulated.pages),
            stale: false, incompleteReason: failure, contractVerified: contractVerified, records: accumulated.records)
    }

    private func handle(_ data: Data) async -> Data {
        do {
            let request = try ReadRequest.parse(data)
            guard paired, auth?.expiresAt ?? .distantPast > Date() else { throw ReadFailure.loginRequired }
            if request.operation == "status" {
                return encode(Status(ok: true, policy: ReadPolicy.id, paired: true, loginRequired: false, checks: checks))
            }
            if request.operation == "diagnostics.verifyReads" { return encode(await pilot()) }
            let result = await read(request)
            // Unverified contracts never export personal records to a normal client.
            guard result.contractVerified else { throw result.incompleteReason ?? ReadFailure.contractPending }
            return encode(result)
        } catch { return encode(ErrorResult(ok: false, error: error as? ReadFailure ?? .schemaMismatch)) }
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data("{\"ok\":false,\"error\":\"schemaMismatch\"}".utf8)
    }

    private func writeReceipt() {
        let receipt = Status(ok: true, policy: ReadPolicy.id, paired: paired,
                             loginRequired: auth?.expiresAt ?? .distantPast <= Date(), checks: checks)
        try? FileManager.default.createDirectory(at: LocalIPC.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = LocalIPC.directory.appendingPathComponent("read-verification.json")
        try? encode(receipt).write(to: path, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    private struct ErrorResult: Encodable { let ok: Bool; let error: ReadFailure }
    private struct Status: Encodable {
        let ok: Bool; let policy: String; let paired: Bool; let loginRequired: Bool; let checks: [ReadCheck]
    }
}
