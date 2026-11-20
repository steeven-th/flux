import SwiftUI

/// Emoji, name and color of a space.
struct SpaceFields: View {
    @Binding var name: String
    @Binding var icon: String
    @Binding var color: String
    /// Offers SF Symbols as well as emojis when given.
    var symbol: Binding<String?>?
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
                        if !value.isEmpty { symbol?.wrappedValue = nil }
                    }
                if let symbol {
                    SymbolButton(symbol: symbol) { icon = "" }
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
                ColorPicker("Other Color", selection: anyColor, supportsOpacity: false)
                    .labelsHidden()
                    .help("Other Color")
            }
        }
    }

    private var anyColor: Binding<Color> {
        Binding(get: { Color(hex: color) }, set: { color = NSColor($0).hexString })
    }
}

/// Opens a grid of SF Symbols for the space's icon.
private struct SymbolButton: View {
    @Binding var symbol: String?
    let onPick: () -> Void
    @State private var isPicking = false

    static let symbols = [
        "house.fill", "briefcase.fill", "person.fill", "person.2.fill", "star.fill", "heart.fill",
        "bolt.fill", "flame.fill", "leaf.fill", "globe", "book.fill", "graduationcap.fill",
        "hammer.fill", "wrench.and.screwdriver.fill", "paintbrush.fill", "camera.fill", "music.note",
        "gamecontroller.fill", "film.fill", "cart.fill", "creditcard.fill", "airplane", "car.fill",
        "bicycle", "pawprint.fill", "cup.and.saucer.fill", "fork.knife", "sun.max.fill", "moon.fill",
        "cloud.fill", "sparkles", "atom", "terminal.fill", "chevron.left.forwardslash.chevron.right",
        "newspaper.fill", "bag.fill", "gift.fill", "flag.fill", "bell.fill", "lock.fill", "tray.fill",
        "folder.fill",
    ]

    var body: some View {
        Button {
            isPicking = true
        } label: {
            Image(systemName: symbol ?? "square.grid.2x2")
                .frame(width: 22, height: 22)
                .foregroundStyle(symbol == nil ? .secondary : .primary)
        }
        .buttonStyle(.borderless)
        .help("Symbol")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Self.symbols, id: \.self) { name in
                        Button {
                            symbol = name
                            onPick()
                            isPicking = false
                        } label: {
                            Image(systemName: name)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.primary.opacity(name == symbol ? 0.15 : 0))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if symbol != nil {
                    Button("No Symbol") {
                        symbol = nil
                        isPicking = false
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(10)
        }
    }
}
