import AppKit
import Carbon

@MainActor
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 0
    private var currentID: UInt32 = 0
    private var pressState = HotKeyPressState()
    private let signature: OSType
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private(set) var suspended = false
    var isRegistered: Bool { reference != nil }

    init(signature: OSType = 0x4B4F4521) {
        self.signature = signature
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var keyID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &keyID) == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            return MainActor.assumeIsolated {
                guard keyID.signature == manager.signature else { return OSStatus(eventNotHandledErr) }
                manager.handle(id: keyID.id, pressed: pressed)
                return noErr
            }
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ key: HotKey) throws {
        guard key.isValid else { throw HotKeyError.invalid }
        try registerUnchecked(key)
    }

    func registerEscape() throws {
        try registerUnchecked(HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0))
    }

    private func registerUnchecked(_ key: HotKey) throws {
        nextID &+= 1
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(key.keyCode, key.modifiers,
            EventHotKeyID(signature: signature, id: nextID), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { throw HotKeyError.unavailable }
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement
        currentID = nextID
        pressState.reset()
    }

    func suspend() {
        suspended = true
        unregister()
    }

    func resume(_ key: HotKey) throws {
        defer { suspended = false }
        if !isRegistered { try register(key) }
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        pressState.reset()
    }

    private func handle(id: UInt32, pressed: Bool) {
        guard id == currentID else { return }
        guard let edge = pressState.handle(pressed: pressed), !suspended else { return }
        switch edge {
        case .pressed: onPress?()
        case .released: onRelease?()
        }
    }

    func invalidate() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
    }
}

enum HotKeyError: LocalizedError {
    case invalid, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: "Include Control, Option, or Command with a key. Escape is reserved for canceling."
        case .unavailable: "That shortcut is already in use or unavailable. Choose another combination."
        }
    }
}
