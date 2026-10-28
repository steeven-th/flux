import SwiftUI

/// An extension's popup page, sized to its content like in Chrome.
struct ExtensionPopupView: View {
    let url: String
    let profile: FLXProfile
    let onClose: () -> Void

    @State private var size = CGSize(width: 320, height: 200)

    var body: some View {
        PopupPage(url: url, profile: profile, size: $size, onClose: onClose)
            .frame(width: size.width, height: size.height)
    }
}

private struct PopupPage: NSViewRepresentable {
    // Chrome's limits for extension popups.
    static let minimumSize = NSSize(width: 25, height: 25)
    static let maximumSize = NSSize(width: 800, height: 600)

    let url: String
    let profile: FLXProfile
    @Binding var size: CGSize
    let onClose: () -> Void

    func makeNSView(context: Context) -> FLXBrowserView {
        let view = FLXBrowserView(url: url, profile: profile)
        view.delegate = context.coordinator
        view.fitToContent(withMinimumSize: Self.minimumSize, maximumSize: Self.maximumSize)
        return view
    }

    func updateNSView(_ nsView: FLXBrowserView, context: Context) {}

    static func dismantleNSView(_ nsView: FLXBrowserView, coordinator: Coordinator) {
        nsView.close()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(size: $size, onClose: onClose)
    }

    @MainActor
    final class Coordinator: NSObject, FLXBrowserViewDelegate {
        let size: Binding<CGSize>
        let onClose: () -> Void

        init(size: Binding<CGSize>, onClose: @escaping () -> Void) {
            self.size = size
            self.onClose = onClose
        }

        func browserView(_ browserView: FLXBrowserView, didResizeToFit size: NSSize) {
            self.size.wrappedValue = size
        }

        func browserViewDidClose(_ browserView: FLXBrowserView) {
            onClose()
        }
    }
}
