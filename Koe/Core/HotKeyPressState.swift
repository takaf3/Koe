/// Turns Carbon hotkey notifications into balanced press/release edges.
struct HotKeyPressState {
    enum Edge: Equatable { case pressed, released }
    private(set) var isDown = false

    mutating func handle(pressed: Bool) -> Edge? {
        guard pressed != isDown else { return nil }
        isDown = pressed
        return pressed ? .pressed : .released
    }

    mutating func reset() { isDown = false }
}
