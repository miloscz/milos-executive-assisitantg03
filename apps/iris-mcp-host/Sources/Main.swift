import AppKit
import Foundation
import Security
import LocalAuthentication

private final class PrivateKeyField: NSSecureTextField {
    override func accessibilityValue() -> String? { nil }
    override func accessibilitySelectedText() -> String? { nil }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
private enum RuntimeVault {
    static let service = "net.iris.mcp-host.transport"
    static var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service,
                                     kSecAttrAccount as String:"openai-tunnel-runtime", kSecAttrSynchronizable as String:false] }
    static func requireHardened() throws {
        var code: SecCode?; var staticCode: SecStaticCode?; var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue:kSecCSStrictValidate), nil) == errSecSuccess,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue:kSecCSSigningInformation), &info) == errSecSuccess,
              let fields = info as? [String:Any], let flags = fields[kSecCodeInfoFlags as String] as? UInt32,
              flags & 0x10000 != 0 else { throw TunnelSetupFailure.appIntegrity }
        let entitlements = fields[kSecCodeInfoEntitlementsDict as String] as? [String:Any] ?? [:]
        for name in ["com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation", "com.apple.security.cs.allow-dyld-environment-variables", "com.apple.security.cs.allow-unsigned-executable-memory"] {
            if entitlements[name] as? Bool == true { throw TunnelSetupFailure.appIntegrity }
        }
    }
    static func save(_ value: String) throws {
        try requireHardened()
        guard let normalized = TunnelPolicy.normalizedRuntimeKey(value) else { throw TunnelSetupFailure.invalidRuntimeKey }
        let data = Data(normalized.utf8)
        var access: SecAccess?
        let creation = SecAccessCreate("Iris MCP — provozní klíč tunelu" as CFString, nil, &access)
        guard creation == errSecSuccess, let access else { throw TunnelSetupFailure.keychainStatus(creation, fallback: .keychainSave) }
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data,kSecAttrAccess as String:access] as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw TunnelSetupFailure.keychainStatus(result, fallback: .keychainSave) }
        var item = query; item[kSecValueData as String] = data; item[kSecAttrAccess as String] = access
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw TunnelSetupFailure.keychainStatus(added, fallback: .keychainSave) }
    }
    static func read(allowInteraction: Bool = true) throws -> String {
        try requireHardened()
        var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
        if !allowInteraction {
            let context = LAContext(); context.interactionNotAllowed = true
            q[kSecUseAuthenticationContext as String] = context
            q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var result:CFTypeRef?
        let copied = SecItemCopyMatching(q as CFDictionary,&result)
        guard copied == errSecSuccess else { throw TunnelSetupFailure.keychainStatus(copied, fallback: .keychainRead) }
        guard let data=result as? Data, let value=String(data:data,encoding:.utf8),
              let normalized = TunnelPolicy.normalizedRuntimeKey(value) else {throw TunnelSetupFailure.storedKeyInvalid}
        return normalized
    }
    static func forget() throws {
        try requireHardened();let result=SecItemDelete(query as CFDictionary)
        guard result==errSecSuccess || result==errSecItemNotFound else {throw TunnelSetupFailure.keychainStatus(result, fallback: .keychainDenied)}
    }
}

@MainActor
final class HostDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let tunnel = NSTextField()
    private let key = PrivateKeyField()
    private let autoConnectButton = NSButton(checkboxWithTitle: "Připojit tunel automaticky po spuštění aplikace", target: nil, action: nil)
    private let message = NSTextField(wrappingLabelWithString:"Připraveno. Toto okno nepoužívá přihlašovací údaje +4U.")
    private var worker: Process?
    private var timer: Timer?
    private var ready = false
    private let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Iris MCP")
    private var health: URL { directory.appendingPathComponent("health.url") }
    private var generation = UUID()
    private var checking = false
    private var lastFailure: TunnelSetupFailure?
    private let redirects = NoRedirect()
    private lazy var session: URLSession = {
        let c=URLSessionConfiguration.ephemeral; c.httpCookieStorage=nil;c.urlCredentialStorage=nil;c.urlCache=nil
        c.connectionProxyDictionary=[:];c.timeoutIntervalForRequest=2;c.timeoutIntervalForResource=2
        return URLSession(configuration:c,delegate:redirects,delegateQueue:nil)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:560),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        // Permit human Screen Sharing administration; the runtime key stays masked and AX-private.
        window.title="Iris MCP — soukromé připojení Aidy";window.sharingType = .readOnly;window.center()
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false
        let title=NSTextField(labelWithString:"Omezené spojení Aidy s Iris");title.font = .boldSystemFont(ofSize:22)
        let instructions=NSTextField(wrappingLabelWithString:"Zadej ID soukromého Secure MCP Tunnel a jeho provozní API klíč OpenAI s oprávněním Tunnels Read + Use. Klíč se uloží jen do klíčenky této aplikace. Nikdy sem nezadávej AC1, AC2 ani token +4U.")
        instructions.preferredMaxLayoutWidth=600;message.preferredMaxLayoutWidth=600
        tunnel.placeholderString="tunnel_…";tunnel.stringValue=UserDefaults.standard.string(forKey:"tunnelID") ?? ""
        key.placeholderString="Provozní API klíč OpenAI; prázdné pole použije uložený klíč"
        autoConnectButton.target = self; autoConnectButton.action = #selector(setAutoConnect)
        autoConnectButton.state = UserDefaults.standard.bool(forKey: "autoConnectTunnel") ? .on : .off
        let buttons=NSStackView();buttons.orientation = .horizontal;buttons.spacing=10
        buttons.addArrangedSubview(NSButton(title:"Uložit a spustit tunel",target:self,action:#selector(start)))
        buttons.addArrangedSubview(NSButton(title:"Zastavit",target:self,action:#selector(stop)))
        buttons.addArrangedSubview(NSButton(title:"Zapomenout klíč",target:self,action:#selector(forget)))
        for view in [title,instructions,NSTextField(labelWithString:"ID tunelu"),tunnel,NSTextField(labelWithString:"Provozní klíč OpenAI"),key,autoConnectButton,buttons,message] {stack.addArrangedSubview(view)}
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24),tunnel.widthAnchor.constraint(equalTo:stack.widthAnchor),key.widthAnchor.constraint(equalTo:stack.widthAnchor)])
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);receipt("stopped")
        if autoConnectButton.state == .on { startTunnel(allowInteraction: false) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.deminiaturize(nil); window.makeKeyAndOrderFront(nil)
        sender.activate(ignoringOtherApps: true)
        return true
    }
    func applicationWillTerminate(_ notification:Notification){stop()}

    @objc private func setAutoConnect() {
        UserDefaults.standard.set(autoConnectButton.state == .on, forKey: "autoConnectTunnel")
    }
    @objc private func start() { startTunnel(allowInteraction: true) }
    private func startTunnel(allowInteraction: Bool) {
        guard worker==nil else{return}
        let id=tunnel.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard TunnelPolicy.validID(id) else { report(.invalidTunnelID);return }
        lastFailure = nil
        UserDefaults.standard.set(id, forKey: "tunnelID") // Non-secret input survives a failed local start.
        do {
            let repo=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            let command=repo.appendingPathComponent("services/iris-mcp/scripts/run-stdio.sh").path
            let executable=Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/tunnel-client")
            // Installation checks precede all access to the runtime-key item.
            guard FileManager.default.isExecutableFile(atPath:command) else { throw TunnelSetupFailure.launcherMissing }
            guard FileManager.default.isExecutableFile(atPath:executable.path) else { throw TunnelSetupFailure.clientMissing }
            guard ["/opt/homebrew/bin/node", "/usr/local/bin/node"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw TunnelSetupFailure.nodeMissing }
            guard let config=TunnelPolicy.config(id:id,command:"/bin/bash '"+command.replacingOccurrences(of:"'",with:"'\\''")+"'") else {throw TunnelSetupFailure.invalidTunnelID}
            if allowInteraction, !key.stringValue.isEmpty {try RuntimeVault.save(key.stringValue)}
            key.stringValue=""
            // Startup never opens an unexpected Keychain prompt or retries a challenge.
            let secret=try RuntimeVault.read(allowInteraction: allowInteraction)
            let configURL=directory.appendingPathComponent("transport.yaml")
            do {
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                try Data(config.utf8).write(to:configURL,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:configURL.path)
            } catch { throw TunnelSetupFailure.configurationWrite }
            try? FileManager.default.removeItem(at:health)
            let process=Process();process.executableURL=executable
            process.arguments=["run","--config",configURL.path,"--health.url-file",health.path,"--mcp.max-concurrent-requests","2","--control-plane.max-inflight","2","--mcp.stdio-send-initialized-notification"]
            process.environment=["HOME":NSHomeDirectory(),"PATH":"/usr/bin:/bin","CONTROL_PLANE_API_KEY":secret]
            process.standardInput=FileHandle.nullDevice;process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            generation=UUID();let epoch=generation
            process.terminationHandler={ [weak self] _ in Task { @MainActor in guard let self,self.generation==epoch else{return};self.worker=nil;self.timer?.invalidate();self.ready=false;self.report(.clientExited) } }
            do { try process.run() } catch { throw TunnelSetupFailure.clientLaunch }
            worker=process
            message.stringValue="Tunel se připojuje. Žádné přihlášení +4U se nespouští.";receipt("starting")
            timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){ [weak self] _ in Task{@MainActor in await self?.check()} }
        } catch { key.stringValue=""; report(error as? TunnelSetupFailure ?? .clientLaunch) }
    }
    private func report(_ failure: TunnelSetupFailure) {
        key.stringValue = ""
        lastFailure = failure; ready = false
        message.stringValue = "\(failure.message) Kód: \(failure.rawValue)."
        receipt("failed")
    }
    @objc private func stop() {
        generation=UUID();timer?.invalidate();timer=nil;worker?.terminate();worker=nil;ready=false;checking=false
        key.stringValue="";lastFailure=nil;message.stringValue="Tunel je zastavený.";receipt("stopped")
    }
    @objc private func forget() {
        stop();do{try RuntimeVault.forget();message.stringValue="Provozní klíč byl odstraněn z klíčenky."}catch{message.stringValue="Klíč se nepodařilo odstranit."}
    }
    private func check() async {
        guard !checking,worker?.isRunning==true,let data=try? Data(contentsOf:health),data.count<=256,
              let text=String(data:data,encoding:.utf8),let url=TunnelPolicy.healthURL(text) else{return}
        checking=true;defer{checking=false};let epoch=generation
        do {
            let (bytes,response)=try await session.bytes(from:url)
            bytes.task.cancel()
            guard epoch==generation else{return}
            ready=(response as? HTTPURLResponse)?.statusCode==200
            message.stringValue=ready ? "Tunel hlásí připravenost. V ChatGPT připoj soukromý MCP plugin Iris přes tento tunel. Poté odeber Aidě přístup k Macu." : "Tunel zatím není připravený. Ověř oprávnění a propojení workspace."
            receipt(ready ? "ready" : "starting")
        } catch {guard epoch==generation else{return};ready=false;receipt("starting")}
    }
    private func receipt(_ stage:String) {
        // Only fixed states. No tunnel ID, URLs, API key, logs or remote responses.
        let object:[String:Any]=["schemaVersion":2,"stage":stage,"running":worker?.isRunning==true,"ready":ready,"failure":lastFailure?.rawValue ?? "none","timestamp":ISO8601DateFormatter().string(from:Date())]
        do{try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try JSONSerialization.data(withJSONObject:object).write(to:directory.appendingPathComponent("verification.json"),options:.atomic)}catch{}
    }
}

@main
struct HostMain {
    @MainActor static func main(){let app=NSApplication.shared;let delegate=HostDelegate();app.delegate=delegate;app.run();withExtendedLifetime(delegate){}}
}
