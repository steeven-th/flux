import SwiftUI

/// Name, emoji and color of a space, for a new one or an existing one.
struct SpaceEditor: View {
    let title: LocalizedStringKey
    let onSave: (_ name: String, _ icon: String?, _ color: String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var icon: String
    @State private var color: String

    init(
        title: LocalizedStringKey,
        space: Space?,
        onSave: @escaping (_ name: String, _ icon: String?, _ color: String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
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
        onSave(trimmedName, icon.isEmpty ? nil : icon, color)
    }
}
