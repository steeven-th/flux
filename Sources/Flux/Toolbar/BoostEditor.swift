import AppKit
import SwiftUI

/// Edits a site's Boost in a window of its own: its style sheet, its script, and the elements
/// zapped off its pages.
@MainActor
enum BoostEditorWindow {
    private static var windows: [String: NSWindow] = [:]

    static func show(host: String, onSave: @escaping () -> Void) {
        if let window = windows[host] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = String(localized: "Boost for \(host)")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: BoostEditor(host: host) { saved in
            if saved { onSave() }
            window.close()
        })
        window.setContentSize(NSSize(width: 620, height: 640))
        window.center()
        windows[host] = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { _ = windows.removeValue(forKey: host) }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct BoostEditor: View {
    let host: String
    let finish: (_ saved: Bool) -> Void

    @State private var boost = Boost()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Applies to \(host) in every space. The script runs apart from the page's own, once the page is parsed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Style").font(.headline)
            CodeEditor(text: $boost.css)
            Text("Script").font(.headline)
            CodeEditor(text: $boost.js)
            if !boost.zapped.isEmpty {
                Text("Zapped Elements").font(.headline)
                List {
                    ForEach(boost.zapped, id: \.self) { selector in
                        HStack {
                            Text(selector).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button {
                                boost.zapped.removeAll { $0 == selector }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Show Again")
                        }
                    }
                }
                .frame(height: 110)
            }
            HStack {
                Spacer()
                Button("Cancel") { finish(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    Boosts.shared.set(boost, forHost: host)
                    finish(true)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 520)
        .onAppear { boost = Boosts.shared.boost(forHost: host) }
    }
}

private struct CodeEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.15)))
    }
}
