import AppKit
import Carbon

struct HotKey: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let initial = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))
    var isValid: Bool {
        let allowed = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let primary = UInt32(cmdKey | optionKey | controlKey)
        let modifierKeys: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        return keyCode < 128 && keyCode != UInt32(kVK_Escape) && !modifierKeys.contains(keyCode)
            && modifiers & primary != 0 && modifiers & ~allowed == 0
    }
    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.keyName(keyCode)
    }
    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        modifiers = value
    }
    static func keyName(_ code: UInt32) -> String {
        let special: [UInt32: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 76: "Enter",
            123: "←", 124: "→", 125: "↓", 126: "↑", 102: "英数", 104: "かな",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let label = special[code] { return label }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
            var state: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &state,
                characters.count, &length, &characters)
            if status == noErr, length > 0 { return String(utf16CodeUnits: characters, count: length).uppercased() }
        }
        return "Key \(code)"
    }
}
