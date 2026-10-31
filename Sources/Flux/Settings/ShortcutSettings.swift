import SwiftUI

struct ShortcutSettings: View {
    let shortcuts: Shortcuts

    @State private var search = ""
    @State private var conflict: PendingConflict?

    private struct PendingConflict: Identifiable {
        let id = UUID()
        let shortcut: KeyShortcut
        let action: Shortcuts.Action
        let conflict: Shortcuts.Conflict
    }

    var body: some View {
        Form {
            Section {
                TextField("Search", text: $search, prompt: Text("Search"))
                    .labelsHidden()
            } footer: {
                Text("Click a shortcut, then type the new one. Delete removes it, Escape cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(menus, id: \.self) { menu in
                Section(menu) {
                    ForEach(shownActions.filter { $0.menu == menu }) { action in
                        row(action)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Restore Defaults", action: shortcuts.resetAll)
                    .disabled(shortcuts.changes.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 600)
        .alert(item: $conflict) { pending in
            let name = pending.shortcut.displayName
            if pending.conflict.canTakeShortcut {
                return Alert(
                    title: Text("“\(name)” is already used by “\(pending.conflict.owner)”."),
                    message: Text("It will be removed from “\(pending.conflict.owner)”."),
                    primaryButton: .default(Text("Replace")) { shortcuts.set(pending.shortcut, for: pending.action) },
                    secondaryButton: .cancel()
                )
            }
            return Alert(title: Text("“\(name)” is used by “\(pending.conflict.owner)”, which keeps its shortcut."))
        }
    }

    private var shownActions: [Shortcuts.Action] {
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return shortcuts.actions }
        return shortcuts.actions.filter { action in
            action.title.localizedCaseInsensitiveContains(text) || action.menu.localizedCaseInsensitiveContains(text)
                || shortcuts.shortcut(for: action)?.displayName.localizedCaseInsensitiveContains(text) == true
        }
    }

    /// In the order of the menu bar.
    private var menus: [String] {
        shownActions.map(\.menu).reduce(into: []) { menus, menu in
            if !menus.contains(menu) { menus.append(menu) }
        }
    }

    private func row(_ action: Shortcuts.Action) -> some View {
        LabeledContent(action.title) {
            HStack(spacing: 6) {
                if shortcuts.isChanged(action) {
                    Button { shortcuts.reset(action) } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to Default")
                }
                ShortcutRecorder(shortcut: shortcuts.shortcut(for: action)) { shortcut in
                    record(shortcut, for: action)
                }
            }
        }
    }

    private func record(_ shortcut: KeyShortcut?, for action: Shortcuts.Action) {
        if let shortcut, let found = shortcuts.conflict(for: shortcut, besides: action) {
            conflict = PendingConflict(shortcut: shortcut, action: action, conflict: found)
        } else {
            shortcuts.set(shortcut, for: action)
        }
    }
}

/// A button showing a shortcut, which records the next one typed once clicked.
struct ShortcutRecorder: View {
    let shortcut: KeyShortcut?
    let onRecord: (KeyShortcut?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    /// Only one recorder listens at a time.
    @MainActor private static var stopActive: (() -> Void)?

    var body: some View {
        Button(action: { isRecording ? stop() : start() }) {
            Group {
                if isRecording {
                    Text("Type Shortcut")
                } else if let shortcut {
                    Text(verbatim: shortcut.displayName)
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 110)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        Self.stopActive?()
        isRecording = true
        Shortcuts.shared?.isRecording = true
        Self.stopActive = stop
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(KeyShortcut.usableModifiers)
        switch (event.keyCode, modifiers.isEmpty) {
        case (53, true):
            stop()
        case (51, true), (117, true):
            stop()
            onRecord(nil)
        default:
            guard let shortcut = KeyShortcut(event: event), shortcut.hasCommandKey else {
                NSSound.beep()
                return
            }
            stop()
            onRecord(shortcut)
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        Shortcuts.shared?.isRecording = false
        Self.stopActive = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
