import SwiftUI
import Speech
import ServiceManagement

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 11) {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Koe").font(.system(size: 22, weight: .semibold))
                        Text("Dictation on your Mac").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { NSApplication.shared.terminate(nil) } label: {
                        Image(systemName: "power").frame(width: 24, height: 24)
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help("Quit Koe").accessibilityLabel("Quit Koe")
                }

                VStack(alignment: .leading, spacing: 8) {
                    languagePicker
                    Text(model.modeDetail)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let warning = model.automaticWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "mic.fill")
                        Text("Hold to dictate").fontWeight(.medium)
                        Spacer()
                        Text(model.shortcut.display)
                    }.foregroundStyle(.blue)
                    Text("Keep the shortcut held while speaking. Release to insert.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Keyboard shortcut")
                        Spacer()
                        Button(model.recordingShortcut ? "Press shortcut…" : model.shortcut.display) {
                            if model.recordingShortcut { model.endShortcutRecording() }
                            else { model.beginShortcutRecording() }
                        }.buttonStyle(.bordered).disabled(model.phase.isBusy)
                            .accessibilityLabel("Change keyboard shortcut, currently \(model.shortcut.display)")
                    }
                    if model.recordingShortcut {
                        Text("Press a key with Control, Option, or Command. Escape cancels.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = model.shortcutError { errorText(error) }
                    HStack {
                        Text("Launch at login")
                        Spacer()
                        Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    if model.loginNeedsApproval {
                        Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }.font(.caption)
                    }
                }

                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Languages").fontWeight(.medium)
                        Spacer()
                        if model.checkingModels { ProgressView().controlSize(.mini) }
                        else {
                            Button { Task { await model.refreshModels() } } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Refresh language availability")
                                .accessibilityLabel("Refresh language availability")
                        }
                    }
                    ForEach(model.enabledLocaleIDs, id: \.self) { id in
                        modelRow(LanguageCatalog.title(for: id, in: model.supportedLocaleIDs), id: id)
                    }
                    addLanguageMenu
                    if model.installing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Downloading language models…").font(.caption)
                        }
                        Text("This can take a few minutes. You can close this menu.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !model.downloadableLocaleIDs.isEmpty {
                        Button(downloadTitle) { model.downloadModels() }
                            .buttonStyle(.bordered).disabled(model.phase.isBusy || model.checkingModels)
                        Text("One-time internet connection for Apple’s models. Dictation then works offline.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if model.modelsReady {
                        Label("Ready without an internet connection", systemImage: "checkmark.shield")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !model.checkingModels, let problem = model.readinessProblem {
                        Text(problem).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = model.setupError { errorText(error) }
                }

                Divider()
                VStack(spacing: 10) {
                    permissionRow("Microphone", granted: model.microphoneAllowed, actionTitle: "Allow") { model.requestMicrophone() }
                    permissionRow("Insert into other apps", granted: model.accessibilityAllowed, actionTitle: "Enable") {
                        TextInserter.requestAccess()
                    }
                }
                if !model.accessibilityAllowed {
                    Text("Enable Accessibility to paste at your cursor. Otherwise, Koe copies the result for you.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !model.lastTranscript.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Last dictation").fontWeight(.medium)
                            Text(model.lastLanguage).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { TextInserter.copy(model.lastTranscript) } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.plain).help("Copy last dictation").accessibilityLabel("Copy last dictation")
                            Button { model.lastTranscript = ""; model.lastInsertionDetail = "" } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).help("Clear transcript").accessibilityLabel("Clear transcript")
                        }
                        Text(model.lastTranscript).textSelection(.enabled).lineLimit(5)
                            .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        if !model.lastInsertionDetail.isEmpty {
                            Text(model.lastInsertionDetail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("Hold to speak. Release to insert. Escape cancels.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }.padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.refreshPermissions() }
        .accessibilityIdentifier("koe.menu")
    }

    private var languagePicker: some View {
        let options: [LanguageMode] = [.automatic] + model.enabledLocaleIDs.map { .fixed($0) }
        let picker = Picker("Language", selection: $model.mode) {
            ForEach(options, id: \.self) { mode in
                Text(segmentTitle(mode)).tag(mode).accessibilityLabel(accessibilityTitle(mode))
            }
        }.labelsHidden().disabled(model.phase.isBusy || model.installing)
        return Group {
            // A segmented control stays legible up to four segments; longer lists get a pop-up.
            if options.count <= 4 { picker.pickerStyle(.segmented) } else { picker.pickerStyle(.menu) }
        }
    }

    private func accessibilityTitle(_ mode: LanguageMode) -> String {
        guard let id = mode.localeID else { return mode.title }
        return LanguageCatalog.name(for: id, in: model.enabledLocaleIDs)
    }

    private func segmentTitle(_ mode: LanguageMode) -> String {
        guard let id = mode.localeID else { return "Auto" }
        return LanguageCatalog.shortTitle(for: id, in: model.enabledLocaleIDs)
    }

    private var addLanguageMenu: some View {
        Menu {
            ForEach(model.availableLocaleIDs, id: \.self) { id in
                Button(LanguageCatalog.title(for: id, in: model.supportedLocaleIDs)) { model.enableLanguage(id) }
            }
        } label: {
            Label("Add language", systemImage: "plus.circle").font(.caption)
        }.menuStyle(.borderlessButton).fixedSize()
            .disabled(model.availableLocaleIDs.isEmpty || model.phase.isBusy || model.installing)
            .accessibilityLabel("Add language")
    }

    private var downloadTitle: String {
        let ids = model.downloadableLocaleIDs
        return ids.count == 1 ? "Download \(LanguageCatalog.languageName(for: ids[0])) model" : "Download language models"
    }

    private func modelRow(_ title: String, id: String) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            switch model.models[id] {
            case .installed: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .downloading: Text("Downloading").foregroundStyle(.secondary)
            case .supported: Text("Download needed").foregroundStyle(.secondary)
            case .unsupported: Text("Unavailable").foregroundStyle(.orange)
            default: Text(model.checkingModels ? "Checking…" : "Unavailable").foregroundStyle(.secondary)
            }
            Button { model.disableLanguage(id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(model.enabledLocaleIDs.count == 1 || model.phase.isBusy || model.installing)
                .help("Remove \(LanguageCatalog.languageName(for: id))")
                .accessibilityLabel("Remove \(LanguageCatalog.languageName(for: id))")
        }.font(.caption)
    }

    private func permissionRow(_ title: String, granted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Allowed") }
            else { Button(actionTitle, action: action).buttonStyle(.bordered).controlSize(.small) }
        }
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
    }
}
