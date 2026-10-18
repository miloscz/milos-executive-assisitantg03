import Foundation
import ConnectCore

/// Independent of read.sock and token lifetime. Owns only fixed, non-secret workflow metadata.
@MainActor
final class AuthController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var remembersPairing = false
    @Published private(set) var status = "Ovládání přes Aidu není spárované."
    private(set) var state = AuthControlState()
    private var server: ReadServer?
    private let stateURL: URL
    private let approvalKey = "rememberedControlPairingV1"
    var context: () -> (valid: Bool, busy: Bool, locked: Bool, codes: Bool, background: Bool) = { (false, false, true, false, false) }
    var begin: () -> Void = {}

    init(stateURL: URL = LocalIPC.directory.appendingPathComponent("auth-workflow.json")) {
        self.stateURL = stateURL
        if let data = try? Data(contentsOf: stateURL), data.count <= 4096,
           let saved = try? JSONDecoder().decode(AuthControlState.self, from: data) { state = saved }
        state.recover(); persist()
    }

    func enable() {
        guard !enabled else { return }
        do {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/IrisControl")
            let hash = try LocalIPC.codeHash(LocalIPC.staticCode(helper))
            let next = ReadServer(approvedHelperHash: hash, path: LocalIPC.authSocketPath,
                                  validate: { _ = try AuthControlRequest.parse($0) }) { [weak self] data in
                self?.handle(data) ?? Data("{\"ok\":false,\"error\":\"unavailable\"}".utf8)
            }
            try next.start(); server = next; enabled = true
            status = "IrisControl je spárovaný pro tento běh Macu. Přihlášení čeká na upozornění a tvůj pokyn Aidě."
        } catch { status = "Párování ovládání se nezdařilo. Přihlášení nebylo spuštěno." }
    }

    /// Called only from unlocked local UI, after pairing the current helper.
    func setRememberPairing(_ remember: Bool) {
        let current = context()
        guard !current.locked, !current.busy else { return }
        if !remember {
            UserDefaults.standard.removeObject(forKey: approvalKey)
            remembersPairing = false
            return
        }
        guard enabled else { return }
        do {
            let approval = try currentApproval()
            UserDefaults.standard.set(try JSONEncoder().encode(approval), forKey: approvalKey)
            remembersPairing = true
            status = "Ovládání se obnoví po spuštění stejné podepsané verze. MFA stále vyžaduje nový pokyn."
        } catch { status = "Souhlas k obnovení párování se nepodařilo uložit." }
    }

    /// Restores the narrow listener only. AuthControlState.recover already removed old notices.
    func restoreRememberedPairing() {
        guard let data = UserDefaults.standard.data(forKey: approvalKey) else { return }
        guard data.count <= 1024,
              let saved = try? JSONDecoder().decode(ControlPairingApproval.self, from: data),
              let current = try? currentApproval(),
              saved.matches(appHash: current.appHash, helperHash: current.helperHash) else {
            UserDefaults.standard.removeObject(forKey: approvalKey)
            status = "Verze aplikace nebo klienta se změnila. Potvrď párování a jeho obnovení znovu místně."
            return
        }
        enable()
        remembersPairing = enabled
        if enabled { status = "Uložené párování stejné podepsané verze je obnovené. Přihlášení nebylo spuštěné." }
    }

    private func currentApproval() throws -> ControlPairingApproval {
        let bundle = Bundle.main.bundleURL
        return try ControlPairingApproval(
            appHash: LocalIPC.codeHash(LocalIPC.staticCode(bundle)),
            helperHash: LocalIPC.codeHash(LocalIPC.staticCode(bundle.appendingPathComponent("Contents/MacOS/IrisControl"))))
    }

    func disable() {
        UserDefaults.standard.removeObject(forKey: approvalKey); remembersPairing = false
        server?.stop(); server = nil; enabled = false
        state.invalidateNotice(); persist()
        status = "Ovládání přes Aidu je vypnuté."
    }

    func began() { state.began(); persist() }
    func finished(_ phase: AuthControlState.Phase) { state.finish(phase); persist() }
    func lock() { state.invalidateNotice(); persist() }

    func handle(_ data: Data, now: Date = Date()) -> Data {
        do {
            guard enabled else { throw AuthControlFailure.unavailable }
            let request = try AuthControlRequest.parse(data)
            let current = context()
            switch request.operation {
            case "status": break
            case "prepare":
                state.prepare(sessionValid: current.valid, now: now); persist()
            case "noticeSent":
                guard !current.locked || current.background else { throw AuthControlFailure.locked }
                try state.markNotice(request.noticeID!, now: now); persist()
            case "start":
                guard !current.locked || current.background else { throw AuthControlFailure.locked }
                guard current.codes else { throw AuthControlFailure.credentialsRequired }
                // Idempotent replay remains harmless even after success/failure.
                if state.requestID == request.requestID { return snapshot(current) }
                guard !current.valid else { throw AuthControlFailure.alreadyAuthenticated }
                guard !current.busy else { throw AuthControlFailure.unavailable }
                if try state.start(notice: request.noticeID!, request: request.requestID!, now: now) {
                    // Persist consumption BEFORE crossing into the credential-owning native flow.
                    guard persist() else { state.finish(.interrupted); throw AuthControlFailure.unavailable }; begin()
                }
            default: throw AuthControlFailure.invalidRequest
            }
            return snapshot(context())
        } catch {
            let code = (error as? AuthControlFailure ?? .invalidRequest).rawValue
            return Data("{\"ok\":false,\"error\":\"\(code)\"}".utf8)
        }
    }

    private func snapshot(_ current: (valid: Bool, busy: Bool, locked: Bool, codes: Bool, background: Bool)) -> Data {
        struct Snapshot: Encodable {
            let ok = true
            let enabled: Bool
            let state: AuthControlState
            let sessionValid: Bool
            let busy: Bool
            let locked: Bool
            let hasCredentials: Bool
            let backgroundLoginEnabled: Bool
            let noticeText = "Pro pokračování práce potřebuji přihlášení do +4U. Až řekneš ‚spusť přihlášení‘, vyvolám MFA. Měj připravený telefon."
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(Snapshot(enabled: enabled, state: state, sessionValid: current.valid,
                                            busy: current.busy, locked: current.locked, hasCredentials: current.codes, backgroundLoginEnabled: current.background)))
            ?? Data("{\"ok\":false,\"error\":\"unavailable\"}".utf8)
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(at: LocalIPC.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
            return true
        } catch {
            // Fail closed: never launch a challenge if a consumed request cannot be saved.
            server?.stop(); server = nil; enabled = false
            status = "Nelze bezpečně uložit stav ovládání. Přihlášení přes Aidu je vypnuté."
            return false
        }
    }
}
