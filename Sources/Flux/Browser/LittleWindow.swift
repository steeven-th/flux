import AppKit
import SwiftUI

/// One link opened from another app, in a window of its own, like Arc's Little Arc. The page can
/// be browsed there and closed, or moved to a space.
@MainActor
@Observable
final class LittleWindowModel: NSObject {
    private(set) var spaceID: UUID
    private(set) var page: FLXBrowserView
    private(set) var url: String
    private(set) var title = ""
    private(set) var favicon: NSImage?

    @ObservationIgnored let state: BrowserState
    /// Called when the page was replaced, after moving to a space of another profile.
    @ObservationIgnored var onPageChange: (() -> Void)?
    /// Called when the page closes itself.
    @ObservationIgnored var onClose: (() -> Void)?

    init?(url: String, spaceID: UUID, state: BrowserState) {
        guard let profile = state.profile(ofSpace: spaceID) else { return nil }
        self.state = state
        self.spaceID = spaceID
        self.url = url
        page = FLXBrowserView(url: url, profile: profile)
        favicon = state.favicon(for: url, inSpace: spaceID)
        super.init()
        page.delegate = self
    }

    var space: Space? {
        state.spaces.first { $0.id == spaceID }
    }

    /// Spaces of the same profile share sign-ins, so the page stays. Another profile needs the
    /// page loaded again with its own cookies.
    func switchTo(_ space: Space) {
        guard space.id != spaceID, let current = self.space else { return }
        spaceID = space.id
        guard current.profileFolder.standardizedFileURL != space.profileFolder.standardizedFileURL,
              let profile = state.profile(ofSpace: space.id) else { return }
        let old = page
        page = FLXBrowserView(url: url, profile: profile)
        page.delegate = self
        onPageChange?()
        old.close()
    }
}

extension LittleWindowModel: FLXBrowserViewDelegate {
    func browserView(_ browserView: FLXBrowserView, didChangeURL url: String) {
        self.url = url
    }

    func browserView(_ browserView: FLXBrowserView, didChangeTitle title: String) {
        self.title = title
    }

    func browserView(_ browserView: FLXBrowserView, didChangeFavicon favicon: NSImage) {
        self.favicon = favicon
    }

    func browserView(_ browserView: FLXBrowserView, didOpenPage page: FLXBrowserView, disposition: FLXOpenDisposition) {
        state.newTab(url: page.currentURL, in: spaceID, page: page, selecting: disposition != .backgroundTab)
    }

    func browserViewDidClose(_ browserView: FLXBrowserView) {
        onClose?()
    }
}

@MainActor
final class LittleWindowController: NSWindowController, NSWindowDelegate {
    private static let barHeight: CGFloat = 38
    private static let margin: CGFloat = 8
    /// Room for the window buttons.
    private static let barLeading: CGFloat = 76

    private static var controllers: [LittleWindowController] = []

    private let model: LittleWindowModel
    private let pageContainer = NSView()
    private var pageMoved = false

    static func show(url: String, inSpace spaceID: UUID, state: BrowserState) {
        guard let model = LittleWindowModel(url: url, spaceID: spaceID, state: state) else { return }
        let controller = LittleWindowController(model: model)
        controllers.append(controller)
        controller.showWindow(nil)
        model.page.focus()
        NSApp.activate()
    }

    /// The little window that has the keyboard, its page window included.
    static var key: LittleWindowController? {
        let key = NSApp.keyWindow
        return controllers.first { $0.window === key || $0.window === key?.parent }
    }

    private init(model: LittleWindowModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)
        window.delegate = self

        let content = NSView()
        let background = NSHostingView(rootView: LittleWindowBackground(model: model))
        let bar = NSHostingView(rootView: LittleWindowBar(model: model) { [weak self] in self?.moveToSpace() })
        // The bar sits in the title bar, next to the window buttons.
        bar.safeAreaRegions = []
        let shadow = PageShadowView()
        for view in [background, bar, shadow, pageContainer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        window.contentView = content
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.barLeading),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.margin),
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
            pageContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.margin),
            pageContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.margin),
            pageContainer.topAnchor.constraint(equalTo: bar.bottomAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.margin),
            shadow.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor, constant: -PageShadowView.outset),
            shadow.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor, constant: PageShadowView.outset),
            shadow.topAnchor.constraint(equalTo: pageContainer.topAnchor, constant: -PageShadowView.outset),
            shadow.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor, constant: PageShadowView.outset),
        ])
        showPage()
        model.onPageChange = { [weak self] in self?.showPage() }
        model.onClose = { [weak self] in self?.close() }

        // Each new one a little lower and to the right, like new windows elsewhere.
        window.center()
        if let last = Self.controllers.last?.window {
            _ = window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    private func showPage() {
        pageContainer.subviews.forEach { $0.removeFromSuperview() }
        let page = model.page
        page.frame = pageContainer.bounds
        page.autoresizingMask = [.width, .height]
        pageContainer.addSubview(page)
        page.focus()
    }

    /// The page moves to the space's Today without loading again, and the window closes.
    func moveToSpace() {
        pageMoved = true
        // Out of this window first, so its page window isn't closed with it.
        model.page.removeFromSuperview()
        model.state.adopt(model.page, url: model.url, title: model.title, favicon: model.favicon, in: model.spaceID)
        close()
        NSApp.windows.first { $0 is MainWindow }?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if !pageMoved { model.page.close() }
        Self.controllers.removeAll { $0 === self }
    }
}

private struct LittleWindowBackground: View {
    let model: LittleWindowModel

    var body: some View {
        (model.space?.color ?? .clear).opacity(SpaceBackground.tintOpacity)
            .ignoresSafeArea()
    }
}

private struct LittleWindowBar: View {
    let model: LittleWindowModel
    let moveToSpace: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                if let space = model.space {
                    SpaceIcon(space: space, isSelected: true)
                    Text(space.name).font(.callout)
                }
                Button { model.page.goBack() } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                    .help("Back")
                    .padding(.leading, 6)
                Button { model.page.goForward() } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                    .help("Forward")
                Spacer()
                if let space = model.space {
                    OpenInSpaceButton(model: model, space: space, action: moveToSpace)
                }
            }
            HStack(spacing: 6) {
                Group {
                    if let favicon = model.favicon {
                        Image(nsImage: favicon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 14, height: 14)
                Text(host)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 320)
        }
        .buttonStyle(.borderless)
        .frame(maxHeight: .infinity)
    }

    private var host: String {
        guard let host = URL(string: model.url)?.host() else { return model.url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// "Open in Space" with the space chosen from the arrow next to it, like a split button.
private struct OpenInSpaceButton: View {
    let model: LittleWindowModel
    let space: Space
    let action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 6) {
                    Text("Open in \(Text(space.name).foregroundColor(space.color).fontWeight(.semibold))")
                    Text(verbatim: "⌘O").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .help("Move this page to the space's Today")
            Divider().frame(height: 14)
            Menu {
                ForEach(model.state.spaces) { other in
                    Toggle(other.name, isOn: Binding(get: { other.id == space.id }, set: { _ in model.switchTo(other) }))
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26, height: 24)
            .help("Space for this page")
        }
        .font(.callout)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.background.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.12)))
    }
}
