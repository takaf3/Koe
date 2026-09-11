import SwiftUI

struct RecordingOverlay: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { model.phase == .choosing || model.phase == .failure }

    var body: some View {
        let size = OverlayLayout.size(for: model.phase)
        Group {
            if expanded { expandedContent }
            else { dictationBar }
        }
        .padding(expanded ? 12 : 8)
        .frame(width: size.width - 8, height: size.height - 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: expanded ? 18 : 24))
        .overlay { RoundedRectangle(cornerRadius: expanded ? 18 : 24).strokeBorder(.white.opacity(0.12)) }
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 18 : 24))
        .colorScheme(.dark)
        .padding(4)
        .accessibilityIdentifier("koe.recording")
    }

    private var dictationBar: some View {
        HStack(spacing: 8) {
            cancelButton
            if model.phase == .recording {
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(model.levelHistory.enumerated()), id: \.offset) { _, sample in
                            Capsule().fill(.white)
                                .frame(width: 2, height: reduceMotion ? 8 : 2 + sample * 16)
                        }
                    }.frame(maxWidth: .infinity).frame(height: 20)
                        .accessibilityLabel("Recording. Release to insert. Microphone level \(Int(model.level * 100)) percent")
                    Text(model.elapsedLabel).font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30)
            } else {
                HStack(spacing: 8) {
                    if model.phase == .preparing || model.phase == .transcribing {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else {
                        Image(systemName: model.noticeSymbol).foregroundStyle(.white)
                    }
                    Text(model.phase == .message ? model.noticeTitle : model.statusTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .help(model.statusTitle)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.statusTitle)
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: model.phase == .failure ? "exclamationmark.circle" : "character.bubble")
                    .foregroundStyle(model.phase == .failure ? .orange : .white)
                Text(model.phase == .failure ? "Dictation paused" : model.statusTitle)
                    .font(.callout).fontWeight(.medium).foregroundStyle(.white)
                Spacer()
                cancelButton
            }
            if model.phase == .failure {
                Text(model.message).font(.callout).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let selection = model.selection {
                Text("The language is uncertain. Select the transcript to use.")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        candidateButton(selection.best)
                        ForEach(selection.alternatives, id: \.localeID) { candidate in
                            candidateButton(candidate)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cancelButton: some View {
        Button { model.cancel() } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75)).frame(width: 20, height: 20)
                .background(.white.opacity(0.09), in: Circle())
        }.buttonStyle(.plain)
            .accessibilityLabel(model.phase.isBusy ? "Cancel dictation" : "Dismiss")
    }

    private func candidateButton(_ candidate: TranscriptCandidate) -> some View {
        Button { model.deliver(candidate) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.languageName).font(.caption).foregroundStyle(.white.opacity(0.65))
                Text(candidate.text).font(.callout).foregroundStyle(.white).lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(8)
        }.buttonStyle(.bordered)
    }
}

final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private let panel: DictationPanel
    private let hosting: NSHostingView<RecordingOverlay>
    private var presentationScreen: NSScreen?

    init(model: AppModel) {
        panel = DictationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.setAccessibilityLabel("Koe dictation")
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hosting = NSHostingView(rootView: RecordingOverlay(model: model))
        // Keep explicit bounds across phase changes: a stale fittingSize can hide the panel.
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func update(phase: DictationPhase) {
        if phase == .idle {
            panel.orderOut(nil)
            presentationScreen = nil
            return
        }
        if presentationScreen == nil {
            let mouse = NSEvent.mouseLocation
            presentationScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        }
        guard let screen = presentationScreen else { return }
        let frame = OverlayLayout.frame(for: phase, in: screen.visibleFrame)
        if panel.frame != frame { panel.setFrame(frame, display: true, animate: false) }
        hosting.setFrameSize(frame.size)
        hosting.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }
}
