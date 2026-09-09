import AppKit

/// Runs production insertion only when the named app is foreground, using a disposable field.
@main struct InsertionCheck {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 3 else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let probe = InsertionProbe(expectedBundle: CommandLine.arguments[1], text: CommandLine.arguments[2])
        Timer.scheduledTimer(timeInterval: 0.05, target: probe, selector: #selector(InsertionProbe.tick(_:)), userInfo: nil, repeats: true)
        withExtendedLifetime(probe) { app.run() }
    }
}

@MainActor private final class InsertionProbe: NSObject {
    let expectedBundle: String
    let text: String
    let deadline = Date().addingTimeInterval(15)
    init(expectedBundle: String, text: String) { self.expectedBundle = expectedBundle; self.text = text }
    @objc func tick(_ timer: Timer) {
        if let destination = NSWorkspace.shared.frontmostApplication, destination.bundleIdentifier == expectedBundle {
            timer.invalidate()
            // Simulate a missing saved AX node, which previously prevented insertion.
            let target = InsertionTarget(application: destination, element: nil)
            print(TextInserter().insert(text, target: target).detail)
            Timer.scheduledTimer(timeInterval: 1.2, target: self, selector: #selector(finish), userInfo: nil, repeats: false)
        } else if Date() >= deadline {
            timer.invalidate()
            print("Destination never became foreground; no insertion attempted.")
            finish()
        }
    }
    @objc func finish() { NSApplication.shared.terminate(nil) }
}
