import AppKit
import SwiftUI
import Combine

@main
enum KoeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var menuScreen: NSScreen?
    private var overlay: OverlayController!
    private var subscriptions = Set<AnyCancellable>()
    private var localEscape: Any?
    private let escapeKey = GlobalHotKey(signature: 0x4B4F4543)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        // Do not register a second shortcut or clear another instance’s active audio file.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
               $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
           }) {
            NSApplication.shared.terminate(nil)
            return
        }
        model = AppModel()
        escapeKey.onPress = { [weak self] in self?.model.cancel() }
        overlay = OverlayController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Koe dictation")
            button.image?.isTemplate = true
            button.toolTip = "Koe — Hold \(model.shortcut.display) to dictate"
            button.target = self
            button.action = #selector(toggleMenu)
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        model.showMenu = { [weak self] in self?.openMenu() }
        model.closeMenu = { [weak self] in self?.popover.performClose(nil) }

        model.$phase.receive(on: RunLoop.main).sink { [weak self] phase in
            guard let self else { return }
            overlay.update(phase: phase)
            if phase.isBusy {
                if !escapeKey.isRegistered { try? escapeKey.registerEscape() }
            } else { escapeKey.unregister() }
            statusItem.button?.image = NSImage(systemSymbolName: phase == .recording ? "mic.fill" : "waveform",
                                               accessibilityDescription: "Koe — \(model.statusTitle)")
            statusItem.button?.contentTintColor = phase == .recording ? .systemRed : nil
        }.store(in: &subscriptions)
        model.$shortcut.sink { [weak self] key in self?.statusItem.button?.toolTip = "Koe — Hold \(key.display) to dictate" }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            self?.model.refreshPermissions()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            self?.popover.performClose(nil)
        }.store(in: &subscriptions)

        localEscape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !model.recordingShortcut, event.keyCode == 53, model.phase != .idle else { return event }
            model.cancel()
            return nil
        }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            openMenu()
        }
    }

    @objc private func toggleMenu() {
        if popover.isShown { popover.performClose(nil) }
        else { openMenu() }
    }

    private func openMenu() {
        guard let button = statusItem?.button else { return }
        guard !popover.isShown else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { model.previousApplication = front }
        model.refreshPermissions()
        // A menu bar item may be on a different display from NSScreen.main.
        // Set bounds before showing and let the ScrollView absorb state changes.
        menuScreen = button.window?.screen ?? NSScreen.screens.first
        let visibleFrame = menuScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = MenuLayout.contentSize(in: visibleFrame)
        let host = NSHostingController(rootView: MenuView(model: model))
        host.sizingOptions = []
        host.view.setFrameSize(size)
        host.preferredContentSize = size
        popover.contentViewController = host
        popover.contentSize = size
        NSApplication.shared.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        guard let window = popover.contentViewController?.view.window, let menuScreen else { return }
        window.setFrameOrigin(MenuLayout.constrainedOrigin(for: window.frame, in: menuScreen.visibleFrame))
    }

    func popoverDidClose(_ notification: Notification) {
        model?.endShortcutRecording()
        menuScreen = nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        if let localEscape { NSEvent.removeMonitor(localEscape) }
        escapeKey.invalidate()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMenu()
        return true
    }
}
