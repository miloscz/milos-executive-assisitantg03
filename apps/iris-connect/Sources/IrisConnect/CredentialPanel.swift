import AppKit

@MainActor
final class ProtectedCodeField: NSSecureTextField {
    override func accessibilityValue() -> String? { nil }
    override func accessibilitySelectedText() -> String? { nil }
}

@MainActor
final class CredentialPanel: NSWindowController, NSWindowDelegate {
    private let first = ProtectedCodeField()
    private let second = ProtectedCodeField()
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let save: (String, String) throws -> Void

    init(save: @escaping (String, String) throws -> Void) {
        self.save = save
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 320),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Přístupové kódy — pouze Iris Connect"
        // Human remote setup is supported; values remain secure fields with no AX value.
        window.sharingType = .readOnly
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        first.placeholderString = "Access Code 1"; second.placeholderString = "Access Code 2"
        for field in [first, second] {
            field.font = .systemFont(ofSize: 15)
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 420).isActive = true
            field.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
        let title = NSTextField(labelWithString: "Údaje zůstanou v klíčence tohoto Macu")
        title.font = .boldSystemFont(ofSize: 16)
        let info = NSTextField(wrappingLabelWithString: "Oba kódy zadávej pouze sem. Aplikace je nebude zobrazovat, kopírovat do souborů ani předávat agentům.")
        info.preferredMaxLayoutWidth = 420
        feedback.textColor = .systemRed
        let button = NSButton(title: "Uložit do klíčenky", target: self, action: #selector(store))
        button.bezelStyle = .rounded
        let stack = NSStackView(views: [title, info, first, second, feedback, button])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 25)
        ])
    }

    required init?(coder: NSCoder) { fatalError("Not supported") }

    @objc private func store() {
        do {
            try save(first.stringValue, second.stringValue)
            clearAndClose()
        } catch {
            // No interpolated credential values or system error descriptions.
            feedback.stringValue = "Uložení se nepodařilo. Zkontroluj vyplnění a přístup ke klíčence."
        }
    }

    func clearAndClose() {
        first.stringValue = ""; second.stringValue = ""; feedback.stringValue = ""
        window?.endEditing(for: nil)
        close()
    }
    override func close() {
        first.stringValue = ""; second.stringValue = ""
        super.close()
    }
    func windowWillClose(_ notification: Notification) {
        first.stringValue = ""; second.stringValue = ""
    }
}
