import AppKit
import ApplicationServices

struct InsertionFeedback {
    let title: String
    let detail: String
    let symbol: String
}

@MainActor
struct InsertionTarget {
    let application: NSRunningApplication
    let element: AXUIElement?

    static func capture(application: NSRunningApplication?) -> InsertionTarget? {
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return InsertionTarget(application: application, element: focusedElement(pid: application.processIdentifier))
    }

    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        return element
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        return (value as? String) == kAXSecureTextFieldSubrole
    }
}

@MainActor
final class TextInserter {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        // The SDK exposes the CFString constant as a mutable global; its documented key is immutable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }

    static func openPrivacy(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    static func copy(_ text: String) -> String {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return "Copied to clipboard"
    }

    func insert(_ text: String, target: InsertionTarget?) -> InsertionFeedback {
        let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let current = target.flatMap { InsertionTarget.focusedElement(pid: $0.application.processIdentifier) }
        let decision = InsertionPolicy.decision(trusted: Self.isTrusted,
            targetPID: target?.application.processIdentifier, foregroundPID: foregroundPID,
            targetTerminated: target?.application.isTerminated ?? false,
            secureField: current.map(InsertionTarget.isSecure) ?? false)
        switch decision {
        case .needsAccessibility:
            return copied(text, detail: "Copied. Enable Accessibility to insert automatically.")
        case .noTarget, .targetClosed:
            return copied(text, detail: "Copied. The destination app is unavailable.")
        case .differentApplication:
            return copied(text, detail: "Copied. A different app is now focused.")
        case .secureField:
            return .init(title: "Not inserted", detail: "Secure field detected. Your transcript is available in Koe.", symbol: "lock")
        case .insert: break
        }
        guard let target else { return copied(text) }
        var settable = DarwinBoolean(false)
        if let current,
           AXUIElementIsAttributeSettable(current, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue,
           AXUIElementSetAttributeValue(current, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            return .init(title: "Inserted", detail: "Inserted into \(target.application.localizedName ?? "your app")", symbol: "checkmark")
        }

        // Missing or recreated AX nodes do not mean keyboard focus changed.
        // Recheck the actual destination immediately before posting paste.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.application.processIdentifier else {
            return copied(text, detail: "Copied. A different app is now focused.")
        }

        // Snapshot every pasteboard type, including non-text data, before using Cmd-V.
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        board.clearContents()
        board.setString(text, forType: .string)
        let ourChange = board.changeCount
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return .init(title: "Copied", detail: "Copied to clipboard", symbol: "doc.on.doc")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(target.application.processIdentifier)
        up.postToPid(target.application.processIdentifier)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            // Never overwrite something the user copied while the paste was in flight.
            guard board.changeCount == ourChange else { return }
            board.clearContents()
            let items = saved.map { contents in
                let item = NSPasteboardItem()
                for (type, data) in contents { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { board.writeObjects(items) }
        }
        return .init(title: "Sent", detail: "Sent to \(target.application.localizedName ?? "your app")", symbol: "checkmark")
    }

    private func copied(_ text: String, detail: String = "Copied to clipboard") -> InsertionFeedback {
        Self.copy(text)
        return .init(title: "Copied", detail: detail, symbol: "doc.on.doc")
    }
}
