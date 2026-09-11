import Foundation

enum OverlayLayout {
    static func size(for phase: DictationPhase) -> CGSize {
        switch phase {
        case .choosing: CGSize(width: 376, height: 376)
        case .failure: CGSize(width: 320, height: 124)
        default: CGSize(width: 216, height: 52)
        }
    }

    static func frame(for phase: DictationPhase, in visibleFrame: CGRect) -> CGRect {
        let preferred = size(for: phase)
        let size = CGSize(width: min(preferred.width, visibleFrame.width - 16),
                          height: min(preferred.height, visibleFrame.height - 16))
        return CGRect(x: visibleFrame.midX - size.width / 2,
                      y: min(visibleFrame.minY + 24, visibleFrame.maxY - size.height - 8),
                      width: size.width, height: size.height)
    }
}
