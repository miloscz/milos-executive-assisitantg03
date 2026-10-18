import XCTest
import JavaScriptCore
@testable import ConnectCore

/// Executes the actual production selector against a synthetic DOM, never a login WebView.
final class LoginPageScriptsTests: XCTestCase {
    private func fixture(buttons: [[String: Any]] = [], formVisible: Bool = false,
                         origin: String = "https://uuidentity.plus4u.net", path: String = EndpointPolicy.loginPath,
                         mainFrame: Bool = true) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, _ in XCTFail("Synthetic selector fixture raised a JavaScript exception") }
        // JavaScriptCore has no browser URL class. Resolve test URLs with Foundation,
        // so the actual same-page predicate is exercised rather than just its catch branch.
        let parseURL: @convention(block) (String, String) -> NSDictionary = { href, base in
            guard let base = URL(string: base), let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let scheme = parts.scheme, let host = parts.host else { return [:] }
            return ["origin": scheme + "://" + host + (parts.port.map { ":\($0)" } ?? ""),
                    "pathname": parts.path, "search": parts.percentEncodedQuery.map { "?" + $0 } ?? "",
                    "username": parts.user ?? "", "password": parts.password ?? ""] as NSDictionary
        }
        context.setObject(parseURL, forKeyedSubscript: "parseFixtureURL" as NSString)
        func json(_ object: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]), as: UTF8.self)
        }
        context.evaluateScript("""
        var clicks = 0;
        var formVisible = \(formVisible ? "true" : "false");
        var location = {origin: \(try json(origin)), pathname: \(try json(path)), search: ''};
        location.href = location.origin + location.pathname;
        var window = {}; window.top = \(mainFrame ? "window" : "{}");
        var specifications = \(try json(buttons));
        var buttons = specifications.map(spec => ({
          tagName: spec.tagName || 'BUTTON', type: spec.type || 'button', disabled: !!spec.disabled, textContent: spec.text || '',
          innerText: spec.innerText || spec.text || '',
          getClientRects: () => spec.hidden ? [] : [1],
          getAttribute: key => key === 'aria-disabled' && spec.ariaDisabled ? 'true' : spec[key] || null,
          closest: () => spec.inert ? {} : null,
          style: {visibility: spec.visibility || 'visible', display: 'block'},
          click: () => { clicks++; if (spec.openForm) formVisible = true; }
        }));
        var document = {
          querySelector: () => ({getClientRects: () => formVisible ? [1] : [], style: {visibility: 'visible', display: 'block'}}),
          querySelectorAll: () => buttons
        };
        var getComputedStyle = element => element.style;
        var URL = function(href, base) {
          var parts = parseFixtureURL(href, base);
          if (!parts.origin) throw new Error('Invalid synthetic URL');
          this.origin = parts.origin; this.pathname = parts.pathname; this.search = parts.search;
          this.username = parts.username; this.password = parts.password;
        };
        """)
        return context
    }

    private func run(_ script: String, in context: JSContext) -> String? {
        context.evaluateScript("(function(){\(script)})()")?.toString()
    }

    func testOfficialCzechAndEnglishChoiceOpensFormWithoutSubmitting() throws {
        for label in ["Pokračovat s +4U Access", "Continue with +4U Access", "+4U Access", "Pokračovat\u{00a0}s\u{00a0}+4U Access",
                      "Pokračovat s+4U Access", "Přihlásit pomocí Plus4U Access", "Přihlásit se pomocí +4U Access", "Plus4U Access"] {
            let context = try fixture(buttons: [["text": label, "openForm": true]])
            XCTAssertEqual(run(LoginPageScripts.methodProbe, in: context), "choiceReady")
            XCTAssertEqual(context.objectForKeyedSubscript("clicks")?.toInt32(), 0)
            XCTAssertEqual(run(LoginPageScripts.selectAccess, in: context), "selected")
            XCTAssertEqual(context.objectForKeyedSubscript("clicks")?.toInt32(), 1)
            XCTAssertEqual(run(LoginPageScripts.methodProbe, in: context), "formReady")
            XCTAssertEqual(run(LoginPageScripts.selectAccess, in: context), "notSelected")
            XCTAssertEqual(context.objectForKeyedSubscript("clicks")?.toInt32(), 1)
        }
    }

    func testOtherProvidersMfaAndUnexpectedLabelsAreNeverClicked() throws {
        let context = try fixture(buttons: ["Continue with Google", "Continue with password", "Confirm MFA", "Delete +4U Access", "Continue with +4U Access account"]
            .map { ["text": $0] })
        XCTAssertEqual(run(LoginPageScripts.methodProbe, in: context), "unsupportedChoice")
        XCTAssertEqual(run(LoginPageScripts.selectAccess, in: context), "notSelected")
        XCTAssertEqual(context.objectForKeyedSubscript("clicks")?.toInt32(), 0)
    }

    func testHiddenDisabledInertAndSubmitButtonsAreNeverClicked() throws {
        let variants: [[String: Any]] = [["hidden": true], ["disabled": true], ["ariaDisabled": true], ["inert": true],
                                       ["visibility": "hidden"], ["type": "submit"]]
        for var variant in variants {
            variant["text"] = "Continue with +4U Access"
            let context = try fixture(buttons: [variant])
            XCTAssertEqual(run(LoginPageScripts.methodProbe, in: context), "waiting")
            XCTAssertEqual(run(LoginPageScripts.selectAccess, in: context), "notSelected")
            XCTAssertEqual(context.objectForKeyedSubscript("clicks")?.toInt32(), 0)
        }
    }

    func testAmbiguousButtonsAreRejected() throws {
        let context = try fixture(buttons: [["text": "+4U Access"], ["text": "Continue with +4U Access"]])
        XCTAssertEqual(run(LoginPageScripts.methodProbe, in: context), "ambiguous")
        XCTAssertEqual(run(LoginPageScripts.selectAccess, in: context), "notSelected")
        XCTAssertEqual(context.objectForKeyedSubscript("clicks")?.toInt32(), 0)
    }

    func testRenderedLabelAndSamePageAnchorOrButtonRole() throws {
        for extra: [String: Any] in [["tagName": "A", "href": "#"], ["tagName": "DIV", "role": "button"],
                                    ["tagName": "A", "href": "https://uuidentity.plus4u.net" + EndpointPolicy.loginPath]] {
            var spec = extra
            spec["text"] = "Hidden icon text Continue with +4U Access"
            spec["innerText"] = "Continue with +4U Access"
            spec["openForm"] = true
            let context = try fixture(buttons: [spec])
            XCTAssertEqual(run(LoginPageScripts.methodProbe, in: context), "choiceReady")
            XCTAssertEqual(run(LoginPageScripts.selectAccess, in: context), "selected")
        }
    }

    func testForeignLinksNewWindowsAndWrongRoleAreNeverClicked() throws {
        for extra: [String: Any] in [["tagName": "A", "href": "https://example.com/"],
                                    ["tagName": "A", "href": "https://uuidentity.plus4u.net/other"],
                                    ["tagName": "A", "href": "https://uuidentity.plus4u.net" + EndpointPolicy.loginPath + "?state=changed"],
                                    ["tagName": "A", "href": "https://user@uuidentity.plus4u.net" + EndpointPolicy.loginPath],
                                    ["tagName": "A", "target": "_blank"], ["tagName": "DIV"],
                                    ["tagName": "INPUT", "role": "button", "type": "submit"]] {
            var spec = extra; spec["text"] = "+4U Access"
            let context = try fixture(buttons: [spec])
            XCTAssertEqual(run(LoginPageScripts.methodProbe, in: context), "waiting")
            XCTAssertEqual(run(LoginPageScripts.selectAccess, in: context), "notSelected")
            XCTAssertEqual(context.objectForKeyedSubscript("clicks")?.toInt32(), 0)
        }
    }

    func testForeignOriginsPathsAndFramesAreDenied() throws {
        for (origin, path, main) in [
            ("https://uuidentity.plus4u.net.evil", EndpointPolicy.loginPath, true),
            ("http://uuidentity.plus4u.net", EndpointPolicy.loginPath, true),
            ("https://uuidentity.plus4u.net:444", EndpointPolicy.loginPath, true),
            ("https://uuidentity.plus4u.net", "/mfa", true),
            ("https://uuidentity.plus4u.net", EndpointPolicy.loginPath, false)
        ] {
            let context = try fixture(buttons: [["text": "+4U Access"]], origin: origin, path: path, mainFrame: main)
            XCTAssertEqual(run(LoginPageScripts.methodProbe, in: context), "denied")
            XCTAssertEqual(run(LoginPageScripts.selectAccess, in: context), "denied")
            XCTAssertEqual(context.objectForKeyedSubscript("clicks")?.toInt32(), 0)
        }
    }
}
