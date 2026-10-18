import SwiftUI
import AppKit
import WebKit

@main
struct IrisConnectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Iris Connect") {
            ContentView(model: model).frame(minWidth: 790, minHeight: 650)
        }
        .defaultSize(width: 920, height: 780)
        .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra("Iris Connect", systemImage: "link.circle") {
            Text(model.status)
            Button("Otevřít Iris Connect") { NSApp.activate(ignoringOtherApps: true); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
            Divider()
            Button("Ukončit") { model.cancel(); NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Permit the human owner to administer the Mini through Screen Sharing.
        // Secret fields are masked; this legacy flag is not a security boundary for agents.
        for window in NSApp.windows { window.sharingType = .readOnly }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "link.circle.fill").font(.system(size: 38)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Iris Connect").font(.title.bold())
                    Text("Soukromá brána do +4U · místní prototyp").foregroundStyle(.secondary)
                }
                Spacer()
                Text("Tento Mac").font(.caption.bold()).padding(8).background(.quaternary, in: Capsule())
            }
            Text(model.status).font(.body).textSelection(.disabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(model.verified ? Color.green.opacity(0.12) : Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button(model.hasCodes ? "Změnit přístupové kódy…" : "Zadat přístupové kódy…") { model.showCredentialEntry() }.disabled(model.locked || model.busy)
                Button("Přihlásit a ověřit čtení") { model.beginLogin() }
                    .buttonStyle(.borderedProminent).tint(.teal).disabled(model.locked || !model.hasCodes || model.busy)
                if model.busy { Button("Zrušit pokus") { model.cancel() }; ProgressView().controlSize(.small) }
                Spacer()
                Button("Zapomenout údaje", role: .destructive) { model.forget() }.disabled(model.locked || !model.hasCodes || model.busy)
            }
            if let webView = model.webView {
                BrowserView(webView: webView)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            } else {
                ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("1. Zadej AC1 a AC2 v soukromém okně aplikace.", systemImage: "key")
                    Label("2. Spusť přihlášení a potvrď MFA u +4U.", systemImage: "iphone")
                    Label("3. Aplikace ověří token a provede jedno čtení identity.", systemImage: "checkmark.shield")
                    Text("Kódy ani tokeny se nepředávají agentům. Čtecí rozhraní používá jen schválené operace pro vlastní agendu a její podklady. Úkoly ani kalendář nemění.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Převzít konfiguraci klienta původní Iris…") { model.importClientConfiguration() }
                        .disabled(model.locked || model.busy)
                    Button("Ověřit přístup aplikace ke klíčence") { model.authorizeStoredKeychainAccess() }
                        .disabled(model.locked || model.busy)
                    Text("Po aktualizaci zde můžeš potvrdit souhlas klíčenky pro tuto aplikaci. Bez přihlášení a bez MFA.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.verified {
                        Divider()
                        Label("Podpis tokenu a čtecí požadavek ověřeny", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        if let expires = model.expiresAt { Text("Token platí do \(expires.formatted(date: .omitted, time: .shortened)).").font(.callout) }
                        Button(model.mfaConfirmedByUser ? "MFA potvrzeno uživatelem" : "Potvrzuji, že jsem dokončil MFA") { model.confirmMFA() }
                            .disabled(model.mfaConfirmedByUser)
                        Text("Toto potvrzení zaznamenává tvoje ověření MFA; aplikace ho nevydává za kryptografický důkaz druhého faktoru.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    AuthControls(control: model.authControl, canConfigure: !model.locked && !model.busy)
                    Toggle("Povolit přihlášení přes MCP při zamčené obrazovce", isOn: Binding(get: { model.backgroundLoginEnabled }, set: { model.setBackgroundLoginEnabled($0) }))
                        .disabled(model.locked || model.busy)
                    Text("Jen po novém pokynu přes Aidu. macOS zůstává zamčený; při požadavku klíčenky na místní souhlas se pokus zastaví. Po restartu musí být přihlášený uživatel. Pokud aplikace nezná počáteční stav zámku, pro nastavení jednou Mac zamkni a odemkni.").font(.caption).foregroundStyle(.secondary)
                    ReadControls(engine: model.reads, authenticated: model.verified, canConfigure: !model.locked && !model.busy)
                    Spacer()
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Připojení Aidy se nastavuje zvlášť v jejím profilu. Místní ovládání nepředává kódy ani tokeny a samo nezahajuje MFA.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).background(RemoteAdministrationWindowView())
    }
}

private struct AuthControls: View {
    @ObservedObject var control: AuthController
    let canConfigure: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Přihlášení přes Aidu").font(.headline)
            Text(control.status).font(.callout)
            Text("Povolíš pouze přibalenému IrisControl zjistit stav, připravit upozornění a po tvém pokynu spustit jeden pokus. Obnovení po restartu lze místně povolit pro stejnou podepsanou verzi.").font(.caption)
            if control.enabled {
                Button("Vypnout ovládání přes Aidu") { control.disable() }
                    .disabled(!canConfigure)
            } else {
                Button("Povolit místní ovládání přihlášení pro Aidu") { control.enable() }
                    .disabled(!canConfigure)
            }
            Toggle("Obnovit toto párování po spuštění aplikace", isOn: Binding(
                get: { control.remembersPairing }, set: { control.setRememberPairing($0) }))
                .disabled(!canConfigure || !control.enabled)
        }
    }
}

private struct ReadControls: View {
    @ObservedObject var engine: ReadEngine
    let authenticated: Bool
    let canConfigure: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Schválené čtení agendy").font(.headline)
            Text(engine.status).font(.callout)
            Button("Najít můj pracovní prostor") { engine.findWorkspace() }
                .disabled(!canConfigure || !authenticated || engine.working || engine.paired)
            if let candidate = engine.candidate, !engine.paired {
                Text(candidate.absoluteString).font(.caption).textSelection(.disabled)
                Text("Potvrzením povolíš tento vlastní prostor a přibalený podepsaný program IrisRead. Párování platí pro tento běh aplikace.").font(.caption)
                Button("Potvrdit vlastní prostor a místního klienta") { engine.pairAndBind() }
                    .disabled(!canConfigure || engine.working || !authenticated)
            }
            if engine.paired {
                Toggle("Obnovit čtecí párování po příštím přihlášení", isOn: Binding(
                    get: { engine.remembersReadBinding }, set: { engine.setRememberReadBinding($0) }))
                    .disabled(!canConfigure || engine.working)
                Text("Jen pro stejný účet, vlastní prostor a stejnou podepsanou verzi aplikace i IrisRead. Nespouští přihlášení ani MFA.").font(.caption)
                Button("Ověřit čtení úkolů a kalendáře") { engine.verifyReads() }.disabled(engine.working)
            }
            ForEach(engine.checks, id: \.operation) { check in
                Text("\(check.operation): \(check.records) záznamů, \(check.pages) stran; \(check.readSucceeded ? "čtení ověřeno" : "čtení neověřeno"); \(check.reason?.rawValue ?? "complete")")
                    .font(.caption)
            }
            if engine.working { ProgressView().controlSize(.small) }
        }
    }
}

private struct RemoteAdministrationWindowView: NSViewRepresentable {
    final class AdministrationView: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.sharingType = .readOnly }
    }
    func makeNSView(context: Context) -> NSView { AdministrationView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct BrowserView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
