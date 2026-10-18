import AppKit
import SwiftUI
import WebKit
import CoreGraphics
import ConnectCore

@MainActor
final class AppModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var status = "Připraveno k nastavení na tomto Macu."
    @Published private(set) var hasCodes = false
    @Published private(set) var busy = false
    @Published private(set) var verified = false
    @Published private(set) var mfaConfirmedByUser = false
    @Published private(set) var expiresAt: Date?
    @Published private(set) var webView: WKWebView?

    private let vault = KeychainVault()
    private let service = OIDCService()
    let reads = ReadEngine()
    let authControl = AuthController()
    private var attempt: LoginAttempt?
    private var client: LegacyClient?
    private var expiryTimer: Timer?
    private var fillTask: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var submittedCodes = false
    private var credentialFillAttempted = false
    private var accessMethodSelectionAttempted = false
    private var accessMethodSelectedByApp = false
    private var loginPageProbe = "notStarted"
    private var exchanging = false
    @Published private(set) var locked = true
    @Published private(set) var backgroundLoginEnabled = UserDefaults.standard.bool(forKey: "backgroundLoginEnabled")
    private var remoteAttempt = false
    private var loginStartedFromMCP = false
    private var loginStartedWhileLocked = false
    private var activity: NSObjectProtocol?
    private var guiSessionAvailable: Bool { CGSessionCopyCurrentDictionary() != nil }
    private var backgroundAllowed: Bool { backgroundLoginEnabled && guiSessionAvailable }
    private var attemptMayContinue: Bool {
        BackgroundLoginPolicy.canContinue(locked: locked, enabled: backgroundAllowed, remoteAttempt: remoteAttempt)
    }

    func setBackgroundLoginEnabled(_ value: Bool) {
        guard !locked, !busy else { return }
        backgroundLoginEnabled = value
        UserDefaults.standard.set(value, forKey: "backgroundLoginEnabled")
        writeReceipt(state: verified ? "authenticated" : "ready")
    }
    private var validationFailures: [ConnectFailure] = []
    private var panel: CredentialPanel?
    private var lockObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        reads.canConfigure = { [weak self] in self.map { !$0.locked && !$0.busy } ?? false }
        // The lock key is not a documented contract. Missing/unknown values fail closed.
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           let value = session["CGSSessionScreenIsLocked"] as? Bool { locked = value }
        if locked { status = "Pro místní nastavení Mac jednou zamkni a odemkni. Přihlášení zatím není spuštěné." }
        hasCodes = vault.contains("access-codes")
        authControl.context = { [weak self] in
            guard let self else { return (false, false, true, false, false) }
            return (self.verified && (self.expiresAt.map { $0 > Date() } ?? false), self.busy, self.locked, self.hasCodes, self.backgroundAllowed)
        }
        authControl.begin = { [weak self] in self?.beginLogin(fromRemote: true) }
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.locked = locked
                    if locked {
                        self.panel?.clearAndClose(); self.panel = nil
                        if !self.backgroundAllowed {
                            self.cancel(); self.authControl.lock(); self.reads.disconnect()
                            self.status = "Mac je zamčený. Přihlášení na pozadí není povolené."
                        } else {
                            if self.busy && !self.remoteAttempt { self.cancel() }
                            self.status = "Mac je zamčený. Omezené MCP zůstává dostupné; přihlášení vyžaduje nový pokyn."
                        }
                    } else {
                        self.hasCodes = self.vault.contains("access-codes")
                        if !self.busy { self.status = self.verified ? "Ověřená relace je připravená." : "Mac je odemčený. Můžeš nastavit přihlášení." }
                    }
                    self.writeReceipt(state: self.busy ? "authenticating" : (self.verified ? "authenticated" : "ready"))
                }
            })
        }
        authControl.restoreRememberedPairing()
        writeReceipt(state: "ready")
    }

    func showCredentialEntry() {
        guard !locked, !busy else { return }
        if let panel { panel.showWindow(nil); return }
        panel = CredentialPanel { [weak self] first, second in
            guard let self, !self.locked else { throw ConnectFailure.cancelled }
            try self.vault.saveCodes(first, second)
            self.hasCodes = true
            self.status = "Přístupové kódy jsou uložené v klíčence. Můžeš spustit přihlášení."
        }
        panel?.showWindow(nil)
        panel?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Unlocked native UI only: allows the owner to approve this signed build locally.
    /// No network request, no authentication attempt and no value leaves this method.
    func authorizeStoredKeychainAccess() {
        guard !locked, !busy else { return }
        do {
            _ = try vault.client()
            _ = try vault.codes()
            // A new process never restores this old token. Removing the unused copy
            // avoids carrying an obsolete build's ACL into the next locked login.
            // No token value is read. A currently verified session is left intact.
            if !verified { try vault.delete("session") }
            hasCodes = true
            status = "Přístup této aplikace k uložené konfiguraci a kódům je ověřený. Přihlášení ani MFA se nespustilo."
        } catch {
            status = "Přístup ke klíčence se neověřil. Potvrď případný místní souhlas pouze pro Iris Connect. Přihlášení nebylo spuštěné."
        }
    }

    /// Human-selected native import only: no CLI, IPC, diagnostics or returned values.
    /// Only literal client constants are parsed; JavaScript is never evaluated.
    func importClientConfiguration() {
        guard !locked, !busy else { return }
        let picker = NSOpenPanel()
        picker.title = "Vybrat konfiguraci klienta původní Iris"
        picker.message = "Vyber původní oidc.js. Aplikace převezme pouze konfiguraci klienta do vlastní klíčenky. Nevybírej soubor s přístupovými kódy nebo tokeny."
        picker.allowsMultipleSelection = false; picker.canChooseDirectories = false
        guard picker.runModal() == .OK, !locked, !busy, let url = picker.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= 524288 else { throw ConnectFailure.configuration }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: 524289), data.count <= 524288,
                  let source = String(data: data, encoding: .utf8) else { throw ConnectFailure.configuration }
            let config = try LegacyClient(source: source)
            try vault.saveClient(config)
            status = "Konfigurace přihlašovacího klienta je uložená v klíčence této aplikace."
        } catch {
            status = "Konfiguraci klienta se nepodařilo bezpečně převzít. Žádné údaje nebyly vypsané."
        }
    }

    func beginLogin(fromRemote: Bool = false) {
        guard BackgroundLoginPolicy.canStart(locked: locked, enabled: backgroundAllowed, fromRemote: fromRemote),
              !busy, hasCodes else { return }
        authControl.began()
        panel?.clearAndClose(); panel = nil
        cleanup()
        remoteAttempt = fromRemote
        loginStartedFromMCP = fromRemote
        loginStartedWhileLocked = locked
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Uživatelem vyžádané přihlášení Iris Connect")
        reads.disconnect()
        verified = false; mfaConfirmedByUser = false; expiresAt = nil
        validationFailures = []
        submittedCodes = false; credentialFillAttempted = false; exchanging = false; busy = true
        accessMethodSelectionAttempted = false; accessMethodSelectedByApp = false
        loginPageProbe = "notStarted"
        status = "Ověřuji konfiguraci +4U."
        writeReceipt(state: "checking_configuration")
        let next = LoginAttempt()
        attempt = next
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fail(.expired) }
        }
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let interactive = BackgroundLoginPolicy.mayUseInteractiveKeychain(locked: self.locked)
                let config: LegacyClient
                if self.vault.contains("client-configuration") {
                    config = try self.vault.client(allowInteraction: interactive)
                } else {
                    // Compatibility on the development Mac only. No secret is exported.
                    config = try LegacyClient.load()
                    try self.vault.saveClient(config, allowInteraction: interactive)
                }
                try await self.service.verifyDiscovery()
                guard !Task.isCancelled, self.attempt?.id == next.id, self.attemptMayContinue else { return }
                self.client = config
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                configuration.userContentController = WKUserContentController() // No native message handlers.
                let view = WKWebView(frame: .zero, configuration: configuration)
                view.isInspectable = false
                view.navigationDelegate = self; view.uiDelegate = self
                self.webView = view
                self.status = "Aplikace automaticky zvolí Plus4U Access a doplní kódy. MFA potvrď na telefonu."
                self.writeReceipt(state: "authenticating")
                view.load(URLRequest(url: try next.authorizationURL(client: config)))
            } catch {
                guard self.attempt?.id == next.id else { return }
                self.fail(error as? ConnectFailure ?? .configuration)
            }
        }
    }

    func cancel() {
        let wasBusy = busy
        cleanup(); busy = false
        if wasBusy { authControl.finished(.cancelled); status = ConnectFailure.cancelled.localizedDescription; writeReceipt(state: "cancelled") }
    }

    func forget() {
        guard !locked else { return }
        cancel(); reads.disconnect(); panel?.clearAndClose(); panel = nil
        do {
            try vault.delete("access-codes"); try vault.delete("session")
            authControl.finished(.idle)
            hasCodes = false; verified = false; mfaConfirmedByUser = false; expiresAt = nil
            status = "Přístupové kódy a token aplikace byly odstraněny z klíčenky."
            writeReceipt(state: "disconnected")
        } catch { fail(.keychain) }
    }

    func confirmMFA() {
        guard verified, expiresAt.map({ $0 > Date() }) == true else { return }
        mfaConfirmedByUser = true
        status = "Přihlášení a čtení jsou ověřené. Potvrzení MFA jsi potvrdil i ty."
        writeReceipt(state: "verified")
    }

    private func cleanup() {
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        remoteAttempt = false
        work?.cancel(); work = nil
        fillTask?.cancel(); fillTask = nil
        expiryTimer?.invalidate(); expiryTimer = nil
        webView?.stopLoading(); webView?.navigationDelegate = nil; webView?.uiDelegate = nil; webView = nil
        attempt = nil; client = nil; exchanging = false
    }

    private func fail(_ failure: ConnectFailure, validationFailures: [ConnectFailure] = []) {
        reads.disconnect()
        cleanup(); busy = false; verified = false; mfaConfirmedByUser = false; expiresAt = nil
        authControl.finished(.failed)
        self.validationFailures = validationFailures
        status = validationFailures.isEmpty ? failure.localizedDescription : validationFailures.map { $0.localizedDescription }.joined(separator: " ")
        writeReceipt(state: failure.rawValue)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard busy, let current = attempt, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if current.matchesCallback(url) {
            decisionHandler(.cancel)
            guard navigationAction.targetFrame?.isMainFrame == true, !exchanging, let config = client else { return }
            do {
                let code = try current.authorizationCode(from: url)
                exchanging = true; fillTask?.cancel(); webView.stopLoading()
                self.webView = nil
                status = "Ověřuji podpis tokenu a skutečné čtení z +4U."
                writeReceipt(state: "verifying")
                work = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let session = try await self.service.finish(code: code, attempt: current, client: config)
                        guard !Task.isCancelled, self.attempt?.id == current.id, self.attemptMayContinue, Date() < current.expiresAt else { return }
                        try self.vault.save(JSONEncoder().encode(session), account: "session", allowInteraction: BackgroundLoginPolicy.mayUseInteractiveKeychain(locked: self.locked))
                        self.expiresAt = session.expiresAt
                        self.verified = true; self.busy = false
                        self.reads.install(session)
                        self.status = "Přihlášení, podpis tokenu a čtení identity z +4U jsou ověřené."
                        self.cleanup()
                        self.writeReceipt(state: "authenticated")
                        self.authControl.finished(.authenticated)
                        self.expiryTimer = Timer.scheduledTimer(withTimeInterval: max(1, session.expiresAt.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                            Task { @MainActor in
                                guard let self else { return }
                                self.verified = false; self.mfaConfirmedByUser = false
                                self.reads.disconnect()
                                self.status = "Platnost ověřené relace skončila. Můžeš spustit nové přihlášení."
                                self.writeReceipt(state: "session_expired")
                                self.authControl.finished(.idle)
                            }
                        }
                    } catch {
                        guard self.attempt?.id == current.id else { return }
                        if let rejected = error as? TokenRejection { self.fail(.token, validationFailures: rejected.reasons) }
                        else { self.fail(error as? ConnectFailure ?? .response) }
                    }
                }
            } catch { fail(error as? ConnectFailure ?? .callback) }
            return
        }
        if navigationAction.targetFrame == nil { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == true && !EndpointPolicy.allowsMainNavigation(url) {
            decisionHandler(.cancel); fail(.policy); return
        }
        // HTTPS frames for CAPTCHA may be needed by the official login page; credentials are never injected into them.
        guard url.scheme == "https" || url.absoluteString == "about:blank" else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !credentialFillAttempted, let url = webView.url, EndpointPolicy.allowsCredentialInsertion(url), let current = attempt else { return }
        fillTask?.cancel()
        fillTask = Task { [weak self, weak webView] in
            for _ in 0..<120 {
                guard let self, let webView, !Task.isCancelled, self.attemptMayContinue, !self.credentialFillAttempted,
                      self.attempt?.id == current.id else { return }
                if await self.fillOfficialForm(webView, attemptID: current.id) { return }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let self, !Task.isCancelled, self.attempt?.id == current.id,
                  !self.credentialFillAttempted else { return }
            self.fail(.loginMethod)
        }
    }

    private func fillOfficialForm(_ view: WKWebView, attemptID: UUID) async -> Bool {
        guard let url = view.url, EndpointPolicy.allowsCredentialInsertion(url), attempt?.id == attemptID, !credentialFillAttempted else { return false }
        do {
            let stage = try await view.callAsyncJavaScript(LoginPageScripts.methodProbe, arguments: [:], in: nil, contentWorld: .page) as? String
            guard !Task.isCancelled, attemptMayContinue, attempt?.id == attemptID else { return true }
            if let stage, ["formReady", "choiceReady", "waiting", "ambiguous", "denied", "unsupportedChoice"].contains(stage), stage != loginPageProbe {
                loginPageProbe = stage
                writeReceipt(state: "authenticating")
            }
            if stage == "choiceReady" {
                guard !accessMethodSelectionAttempted else { return false }
                // Mark before dispatch: even a destroyed JS reply must not cause a repeated click.
                accessMethodSelectionAttempted = true
                let result = try await view.callAsyncJavaScript(LoginPageScripts.selectAccess, arguments: [:], in: nil, contentWorld: .page) as? String
                guard !Task.isCancelled, attemptMayContinue, attempt?.id == attemptID else { return true }
                if result == "selected" {
                    accessMethodSelectedByApp = true
                    status = "Plus4U Access zvolila aplikace. Čekám na oficiální formulář přístupových kódů."
                    writeReceipt(state: "access_method_selected")
                }
                return false
            }
            if stage == "ambiguous" || stage == "denied" || stage == "unsupportedChoice" { fail(.loginMethod); return true }
            guard stage == "formReady" else { return false }
            // Presence test returns only a boolean, never HTML or field values.
            let ready = try await view.callAsyncJavaScript(Self.presenceScript, arguments: [:], in: nil, contentWorld: .page) as? Bool
            guard ready == true, !Task.isCancelled, attemptMayContinue, attempt?.id == attemptID else { return false }
            let codes = try vault.codes(allowInteraction: BackgroundLoginPolicy.mayUseInteractiveKeychain(locked: locked)) // No published property, renderer binding, logging or IPC.
            // At most one credential submission attempt, even if navigation destroys the JS reply.
            credentialFillAttempted = true
            let result = try await view.callAsyncJavaScript(Self.fillScript,
                arguments: ["first": codes.first, "second": codes.second], in: nil, contentWorld: .page) as? Bool
            guard attempt?.id == attemptID else { return true }
            if result == true {
                submittedCodes = true
                status = "Přístupové kódy byly odeslány oficiálním formulářem. Dokonči MFA v +4U."
                writeReceipt(state: "credentials_submitted")
                return true
            }
            status = "Formulář se během doplňování změnil. Případně zruš pokus a spusť ho znovu."
            writeReceipt(state: "credentials_submission_unconfirmed")
            return true
        } catch {
            // Never surface WebKit error text: it might contain evaluated script arguments.
            guard attempt?.id == attemptID else { return true }
            if error as? ConnectFailure == .keychain { fail(.keychain); return true }
            if credentialFillAttempted {
                status = "Dokonči přihlášení a MFA v okně +4U. Automatické doplnění se nebude opakovat."
                writeReceipt(state: "credentials_submission_unconfirmed")
                return true
            }
            if accessMethodSelectionAttempted { return false }
            fail(.response); return true
        }
    }

    private static let originGuard = LoginPageScripts.originGuard
    private static var presenceScript: String {
        """
        if (!(\(originGuard))) return false;
        const a = document.querySelector('input[name="accessCode1"]');
        const b = document.querySelector('input[name="accessCode2"]');
        return !!(a && b && !a.value && !b.value && a.form && a.form === b.form && a.getClientRects().length && b.getClientRects().length
          && new URL(a.form.action, location.href).origin === location.origin
          && new URL(a.form.action, location.href).pathname.endsWith('/authAccessCodes/authenticate')
          && a.form.method.toLowerCase() === 'post');
        """
    }
    private static var fillScript: String {
        """
        if (!(\(originGuard))) return false;
        const a = document.querySelector('input[name="accessCode1"]');
        const b = document.querySelector('input[name="accessCode2"]');
        if (!(a && b && a.form && a.form === b.form && a.getClientRects().length && b.getClientRects().length
          && new URL(a.form.action, location.href).origin === location.origin
          && new URL(a.form.action, location.href).pathname.endsWith('/authAccessCodes/authenticate')
          && a.form.method.toLowerCase() === 'post')) return false;
        if (a.value || b.value) return false;
        a.type = 'password'; b.type = 'password';
        const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
        setter.call(a, first); a.dispatchEvent(new Event('input', {bubbles:true})); a.dispatchEvent(new Event('change', {bubbles:true}));
        setter.call(b, second); b.dispatchEvent(new Event('input', {bubbles:true})); b.dispatchEvent(new Event('change', {bubbles:true}));
        await new Promise(resolve => setTimeout(resolve, 120));
        if (!(\(originGuard))) return false;
        if (!a.form || a.form !== b.form || new URL(a.form.action, location.href).origin !== location.origin
          || !new URL(a.form.action, location.href).pathname.endsWith('/authAccessCodes/authenticate')
          || a.form.method.toLowerCase() !== 'post') return false;
        a.form.requestSubmit();
        return true;
        """
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled, !exchanging { fail(.transport) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled, !exchanging { fail(.transport) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail(.response) }

    /// The ONLY agent-readable artifact. Fixed fields, no identity, URLs, response bodies or credentials.
    private func writeReceipt(state: String) {
        let receipt = VerificationReceipt(state: state, timestamp: Date(), tokenSignatureVerified: verified,
            readProbePassed: verified, credentialsSubmittedByApp: submittedCodes, mfaConfirmedByUser: mfaConfirmedByUser,
            accessMethodSelectionAttempted: accessMethodSelectionAttempted, accessMethodSelectedByApp: accessMethodSelectedByApp,
            loginPageProbe: loginPageProbe, screenLocked: locked, backgroundLoginEnabled: backgroundLoginEnabled,
            backgroundAttempt: loginStartedFromMCP && loginStartedWhileLocked,
            validUntil: expiresAt, validationFailures: validationFailures.map(\.rawValue))
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Iris Connect", isDirectory: true) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipt).write(to: directory.appendingPathComponent("verification.json"), options: .atomic)
        } catch { /* Diagnostics must never fall back to printing payloads. */ }
    }
}

private struct VerificationReceipt: Codable {
    let state: String
    let timestamp: Date
    let tokenSignatureVerified: Bool
    let readProbePassed: Bool
    let credentialsSubmittedByApp: Bool
    let mfaConfirmedByUser: Bool
    let accessMethodSelectionAttempted: Bool
    let accessMethodSelectedByApp: Bool
    let loginPageProbe: String
    let screenLocked: Bool
    let backgroundLoginEnabled: Bool
    let backgroundAttempt: Bool
    let validUntil: Date?
    let validationFailures: [String]
}
