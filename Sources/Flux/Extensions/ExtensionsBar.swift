import SwiftUI

/// The icons of the selected space's extensions. Clicking one opens its popup.
struct ExtensionsBar: View {
    let extensions: [InstalledExtension]
    let profile: FLXProfile

    @State private var openPopupID: String?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(extensions) { item in
                button(for: item)
            }
            Spacer(minLength: 0)
        }
    }

    private func button(for item: InstalledExtension) -> some View {
        Button {
            openPopupID = item.id
        } label: {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                }
            }
            .frame(width: 18, height: 18)
            .padding(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(item.name)
        .disabled(item.popupURL == nil)
        .popover(isPresented: Binding(
            get: { openPopupID == item.id },
            set: { if !$0 { openPopupID = nil } }
        ), arrowEdge: .bottom) {
            if let url = item.popupURL {
                ExtensionPopupView(url: url, profile: profile) { openPopupID = nil }
            }
        }
    }
}
