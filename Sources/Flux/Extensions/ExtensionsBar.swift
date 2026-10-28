import SwiftUI

/// The icons of the selected space's extensions. Clicking one opens its popup.
struct ExtensionsBar: View {
    let extensions: [InstalledExtension]
    let profile: FLXProfile

    var body: some View {
        HStack(spacing: 4) {
            ForEach(extensions) { item in
                ExtensionButton(item: item, profile: profile)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ExtensionButton: View {
    let item: InstalledExtension
    let profile: FLXProfile

    @State private var anchor = AnchorView()

    var body: some View {
        Button {
            if let url = item.popupURL {
                ExtensionPopupPanel.show(url: url, profile: profile, below: anchor)
            }
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
        .background(AnchorReader(view: anchor))
    }
}

/// An AppKit view laid out behind a SwiftUI view, to know where that view is on screen.
final class AnchorView: NSView {}

private struct AnchorReader: NSViewRepresentable {
    let view: AnchorView

    func makeNSView(context: Context) -> AnchorView { view }
    func updateNSView(_ nsView: AnchorView, context: Context) {}
}
