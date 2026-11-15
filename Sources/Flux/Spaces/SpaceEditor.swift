import SwiftUI

/// Name, emoji and color of a space, for a new one or an existing one. A new space can use the
/// profile of existing ones instead of its own.
struct SpaceEditor: View {
    let title: LocalizedStringKey
    /// The profiles a new space can share, empty for an existing space.
    let profiles: [BrowserState.Profile]
    /// The other spaces using the profile of the space edited.
    let sharesProfileWith: [String]
    let onSave: (_ name: String, _ icon: String?, _ color: String, _ sharingProfileOf: UUID?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var sharedSpaceID: UUID?

    init(
        title: LocalizedStringKey,
        space: Space?,
        profiles: [BrowserState.Profile] = [],
        sharesProfileWith: [String] = [],
        onSave: @escaping (_ name: String, _ icon: String?, _ color: String, _ sharingProfileOf: UUID?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.profiles = profiles
        self.sharesProfileWith = sharesProfileWith
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: space?.name ?? "")
        _icon = State(initialValue: space?.icon ?? "")
        _color = State(initialValue: space?.colorHex ?? BrowserState.spaceColors[0])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            SpaceFields(name: $name, icon: $icon, color: $color, onSubmit: save)

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
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, icon.isEmpty ? nil : icon, color, sharedSpaceID)
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
