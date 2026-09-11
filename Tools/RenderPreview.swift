import AppKit
import SwiftUI

/// Renders only Koe’s own views to images; does not capture the desktop or use the microphone.
@main struct RenderPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel(startServices: false)
        model.models = ["en-US": .installed, "ja-JP": .installed, "fr-FR": .installed]
        model.checkingModels = false
        try render(MenuView(model: model).background(Color(nsColor: .windowBackgroundColor)),
                   size: NSSize(width: 370, height: 620), name: "menu")
        model.phase = .recording
        model.level = 0.65
        model.levelHistory = (0..<23).map { 0.1 + abs(sin(Double($0) * 0.7)) * 0.75 }
        model.elapsed = 12
        try render(RecordingOverlay(model: model), size: OverlayLayout.size(for: .recording), name: "recording")
        model.phase = .transcribing
        try render(RecordingOverlay(model: model), size: OverlayLayout.size(for: .transcribing), name: "transcribing")
        model.phase = .message
        model.noticeTitle = "Sent"
        model.message = "Sent to an application with a very long name"
        try render(RecordingOverlay(model: model), size: OverlayLayout.size(for: .message), name: "sent")
        model.noticeTitle = "Copied"
        model.noticeSymbol = "doc.on.doc"
        model.message = "Copied. Enable Accessibility to insert automatically."
        try render(RecordingOverlay(model: model), size: OverlayLayout.size(for: .message), name: "copied")
        model.phase = .choosing
        model.selection = .init(best: .init(localeID: "en-US", text: "Hello, how are you?", confidence: 0.80, audioCoverage: 1),
                                alternatives: [.init(localeID: "ja-JP", text: "こんにちは、お元気ですか？", confidence: 0.79, audioCoverage: 1),
                                               .init(localeID: "fr-FR", text: "Bonjour, comment allez-vous ?", confidence: 0.78, audioCoverage: 1)],
                                isUncertain: true)
        try render(RecordingOverlay(model: model), size: OverlayLayout.size(for: .choosing), name: "language-choice")
    }

    @MainActor static func render<V: View>(_ content: V, size: NSSize, name: String) throws {
        let view = NSHostingView(rootView: content)
        view.appearance = NSAppearance(named: name == "menu" ? .aqua : .darkAqua)
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: image)
        if let data = image.representation(using: .png, properties: [:]) {
            try data.write(to: URL(fileURLWithPath: "build/\(name).png"))
            print("Rendered build/\(name).png")
        }
    }
}
