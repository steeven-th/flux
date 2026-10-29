import SwiftUI

/// Emoji, name and color of a space.
struct SpaceFields: View {
    @Binding var name: String
    @Binding var icon: String
    @Binding var color: String
    var onSubmit: () -> Void = {}

    @FocusState private var isEditingIcon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .onSubmit(onSubmit)
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
        }
    }
}
