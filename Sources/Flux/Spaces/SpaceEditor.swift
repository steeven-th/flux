import SwiftUI

/// Name, emoji and color of a space, for a new one or an existing one.
struct SpaceEditor: View {
    let title: String
    let onSave: (_ name: String, _ icon: String?, _ color: String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @FocusState private var isEditingIcon: Bool

    init(
        title: String,
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

            HStack {
                TextField("Emoji", text: $icon)
                    .frame(width: 52)
                    .focused($isEditingIcon)
                    // Every click, not only the one that focuses the field. The system emoji
                    // picker types into the focused field.
                    .simultaneousGesture(TapGesture().onEnded {
                        isEditingIcon = true
                        NSApp.orderFrontCharacterPalette(nil)
                    })
                    .onChange(of: icon) { _, value in
                        // One emoji at most: keep the last character typed.
                        if value.count > 1 { icon = String(value.suffix(1)) }
                    }
                TextField("Name", text: $name)
                    .onSubmit(save)
            }
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                ForEach(BrowserState.spaceColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle().strokeBorder(.primary, lineWidth: hex == color ? 2 : 0)
                        }
                        .onTapGesture { color = hex }
                }
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
        onSave(trimmedName, icon.isEmpty ? nil : icon, color)
    }
}
