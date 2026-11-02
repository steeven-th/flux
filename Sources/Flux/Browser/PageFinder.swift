import AppKit
import Observation
import SwiftUI

/// A search for text in a page, and the state of its bar. Each tab and little window has its own,
/// kept while the page changes.
@MainActor
@Observable
final class PageFinder {
    private(set) var isShown = false
    var text = "" {
        didSet { if text != oldValue { search() } }
    }
    private(set) var matchCount = 0
    /// From 1, 0 without a match.
    private(set) var activeMatch = 0
    /// Changes each time the bar is asked for, so it takes the keyboard again.
    private(set) var focusRequest = 0

    @ObservationIgnored private let page: () -> FLXBrowserView?

    init(page: @escaping () -> FLXBrowserView?) {
        self.page = page
    }

    func show() {
        if !isShown {
            isShown = true
            search()
        }
        focusRequest += 1
    }

    /// Searches for the page's selection, like ⌘E elsewhere on macOS.
    func findSelection() {
        page()?.evaluateJavaScript("getSelection().toString()") { [weak self] value in
            guard let self, let selection = value as? String, !selection.isEmpty else { return }
            text = selection
            show()
        }
    }

    func next() {
        move(forward: true)
    }

    func previous() {
        move(forward: false)
    }

    func close() {
        isShown = false
        page()?.stopFinding()
        (matchCount, activeMatch) = (0, 0)
        page()?.focus()
    }

    /// Chromium sends -1 for a number that hasn't changed since its last update.
    func update(matchCount: Int, activeMatch: Int) {
        if matchCount >= 0 { self.matchCount = matchCount }
        if activeMatch >= 0 { self.activeMatch = activeMatch }
    }

    /// A page loaded since has new matches.
    func pageDidLoad() {
        if isShown { search() }
    }

    private func move(forward: Bool) {
        guard isShown, !text.isEmpty else { return show() }
        page()?.findText(text, forward: forward, findNext: true)
    }

    private func search() {
        guard !text.isEmpty else {
            page()?.stopFinding()
            (matchCount, activeMatch) = (0, 0)
            return
        }
        // A new search only highlights the matches. Going on to the next one selects the first,
        // as Chrome does as you type. Without stopping the last search first, Chromium would go
        // on from its match while counting from the new search's first.
        page()?.stopFinding()
        page()?.findText(text, forward: true, findNext: false)
        page()?.findText(text, forward: true, findNext: true)
    }
}

/// The search bar, at the top right of the page.
struct FindBar: View {
    @Bindable var finder: PageFinder
    @FocusState private var isFocused: Bool

    static let size = NSSize(width: 340, height: 44)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in Page", text: $finder.text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onKeyPress(.return, phases: .down) { press in
                    press.modifiers.contains(.shift) ? finder.previous() : finder.next()
                    return .handled
                }
                .onExitCommand(perform: finder.close)
            if !finder.text.isEmpty {
                Group {
                    if finder.matchCount == 0 {
                        Text("No Results")
                    } else {
                        Text("\(finder.activeMatch) of \(finder.matchCount)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
            }
            Button(action: finder.previous) { Image(systemName: "chevron.up") }
                .help("Find Previous")
                .disabled(finder.matchCount == 0)
            Button(action: finder.next) { Image(systemName: "chevron.down") }
                .help("Find Next")
                .disabled(finder.matchCount == 0)
            Button(action: finder.close) { Image(systemName: "xmark") }
                .help("Close")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(width: Self.size.width - 12, height: Self.size.height - 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear { isFocused = true }
        .onChange(of: finder.focusRequest) { isFocused = true }
    }
}

/// The bar's window. Pages are windows of their own, so the bar has to be one too, over them.
@MainActor
final class FindBarWindow {
    private let window: NSWindow
    private var shownRequest: Int?
    private let finder: PageFinder

    init(finder: PageFinder) {
        self.finder = finder
        window = KeyableWindow(contentRect: NSRect(origin: .zero, size: FindBar.size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        let host = NSHostingView(rootView: FindBar(finder: finder))
        host.sizingOptions = []
        window.contentView = host
    }

    /// At the top right of `pageFrame`, in screen coordinates. Added again each time, so it stays
    /// above page windows added since.
    func show(atTopRightOf pageFrame: NSRect, over host: NSWindow) {
        let size = FindBar.size
        let origin = NSPoint(x: pageFrame.maxX - size.width - 8, y: pageFrame.maxY - size.height - 8)
        host.removeChildWindow(window)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        host.addChildWindow(window, ordered: .above)
        if shownRequest != finder.focusRequest {
            shownRequest = finder.focusRequest
            window.makeKey()
        }
    }

    func hide() {
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }
}

/// Borderless windows don't take the keyboard unless they say so.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
