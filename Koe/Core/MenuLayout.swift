import Foundation

enum MenuLayout {
    static let preferredSize = CGSize(width: 370, height: 620)

    static func contentSize(in visibleFrame: CGRect) -> CGSize {
        // Leave room for the popover's arrow, rounded border, and screen margins.
        CGSize(width: min(preferredSize.width, max(1, visibleFrame.width - 32)),
               height: min(preferredSize.height, max(1, visibleFrame.height - 40)))
    }

    static func constrainedOrigin(for windowFrame: CGRect, in visibleFrame: CGRect) -> CGPoint {
        let bounds = visibleFrame.insetBy(dx: 6, dy: 6)
        return CGPoint(
            x: min(max(windowFrame.minX, bounds.minX), max(bounds.minX, bounds.maxX - windowFrame.width)),
            y: min(max(windowFrame.minY, bounds.minY), max(bounds.minY, bounds.maxY - windowFrame.height)))
    }
}
