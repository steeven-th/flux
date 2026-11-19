import SwiftUI

/// Name, emoji and look of a space, for a new one or an existing one. An existing space shows its
/// new look in the window while it's being edited, as in Arc. Only Save keeps the changes: a click
/// away from the editor asks first. A new space can use the profile of existing ones instead of
/// its own.
struct SpaceEditor: View {
    let title: LocalizedStringKey
    /// The profiles a new space can share, empty for an existing space.
    let profiles: [BrowserState.Profile]
    /// The other spaces using the profile of the space edited.
    let sharesProfileWith: [String]
    let onSave: (_ name: String, _ icon: String?, _ theme: SpaceTheme, _ sharingProfileOf: UUID?) -> Void
    let onCancel: () -> Void
    let onPreview: ((SpaceTheme) -> Void)?

    @State private var name: String
    @State private var icon: String
    @State private var theme: SpaceTheme
    @State private var sharedSpaceID: UUID?
    @State private var isFinished = false
    /// The look before the editor opened. The window redraws the editor with each preview.
    @State private var originalTheme: SpaceTheme?
    @State private var originalName: String
    @State private var originalIcon: String
    @State private var clickMonitor: Any?

    init(
        title: LocalizedStringKey,
        space: Space?,
        profiles: [BrowserState.Profile] = [],
        sharesProfileWith: [String] = [],
        onSave: @escaping (_ name: String, _ icon: String?, _ theme: SpaceTheme, _ sharingProfileOf: UUID?) -> Void,
        onCancel: @escaping () -> Void,
        onPreview: ((SpaceTheme) -> Void)? = nil
    ) {
        self.title = title
        self.profiles = profiles
        self.sharesProfileWith = sharesProfileWith
        self.onSave = onSave
        self.onCancel = onCancel
        self.onPreview = onPreview
        _originalTheme = State(initialValue: space?.theme)
        _name = State(initialValue: space?.name ?? "")
        _icon = State(initialValue: space?.icon ?? "")
        _originalName = State(initialValue: space?.name ?? "")
        _originalIcon = State(initialValue: space?.icon ?? "")
        _theme = State(initialValue: space?.theme ?? SpaceTheme(color: BrowserState.spaceColors[0]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            SpaceFields(name: $name, icon: $icon, color: $theme.color, onSubmit: save)

            HStack(spacing: 8) {
                Text("Intensity")
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(.secondary)
                Slider(value: $theme.tint, in: SpaceTheme.tintRange)
                    .labelsHidden()
                Image(systemName: "circle.fill")
                    .foregroundStyle(Color(hex: theme.color))
            }

            if !profiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Profile", selection: $sharedSpaceID) {
                        Text("Its Own").tag(UUID?.none)
                        Divider()
                        ForEach(profiles) { profile in
                            Text("Same as \(profile.name)").tag(profile.spaces.first?.id)
                        }
                    }
                    (sharedSpaceID == nil
                        ? Text("Keeps its sign-ins, passwords, history and extensions apart.")
                        : Text("Shares its sign-ins, passwords, history and extensions with these spaces."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !sharesProfileWith.isEmpty {
                SharedProfileLabel(spaces: sharesProfileWith)
            }

            HStack {
                Button {
                    theme = SpaceTheme.random()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .help("Pick colors at random")
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onChange(of: theme) { onPreview?(theme) }
        .interactiveDismissDisabled(hasChanges)
        .onAppear { watchClicksAway() }
        .onDisappear {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            Self.closeColorPanel()
            if !isFinished { cancel() }
        }
    }

    private var hasChanges: Bool {
        name != originalName || icon != originalIcon || (originalTheme.map { $0 != theme } ?? false)
    }

    /// A click outside the editor, and outside the color panel, asks what to do with the changes
    /// instead of closing it.
    private func watchClicksAway() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            guard !isFinished, hasChanges, NSApp.modalWindow == nil, let window = event.window, !(window is NSColorPanel),
                  !String(describing: type(of: window)).contains("Popover") else { return event }
            DispatchQueue.main.async { askToClose() }
            return nil
        }
    }

    private func askToClose() {
        guard !isFinished else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save the changes to this space?")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Discard Changes"))
        alert.addButton(withTitle: String(localized: "Keep Editing"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: save()
        case .alertSecondButtonReturn: cancel()
        default: break
        }
    }

    /// The color well's panel is the app's, and outlives the editor. SwiftUI only lets the editor
    /// go seconds after its popover closed.
    static func closeColorPanel() {
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        isFinished = true
        Self.closeColorPanel()
        onSave(trimmedName, icon.isEmpty ? nil : icon, theme, sharedSpaceID)
    }

    private func cancel() {
        isFinished = true
        Self.closeColorPanel()
        if let originalTheme { onPreview?(originalTheme) }
        onCancel()
    }
}

/// Spaces sharing a profile look like any others in the sidebar, but share their sign-ins.
struct SharedProfileLabel: View {
    let spaces: [String]

    var body: some View {
        Label("Shares sign-ins with \(spaces.formatted(.list(type: .and)))", systemImage: "person.2.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .help("Same profile: history, passwords, sign-ins and extensions are shared.")
    }
}
