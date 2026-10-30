import AppKit
import SwiftUI

/// The browsers Flux imports from. Each one shows its own choices once picked.
enum ImportSource: CaseIterable, Identifiable {
    case arc

    var id: Self { self }

    var name: String {
        switch self {
        case .arc: "Arc"
        }
    }

    private var bundleIdentifier: String {
        switch self {
        case .arc: "company.thebrowser.Browser"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .arc: ArcLibrary.isInstalled
        }
    }

    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// From File > Import from Another Browser: the browsers Flux knows, then what to bring from the
/// one picked.
@MainActor
final class ImportWindowController: NSWindowController {
    private static var shared: ImportWindowController?

    static func show(state: BrowserState) {
        let controller = shared ?? ImportWindowController(state: state)
        shared = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate()
    }

    private init(state: BrowserState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = String(localized: "Import from Another Browser")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: ImportView(state: state) { [weak self] in
            self?.close()
            Self.shared = nil
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }
}

private struct ImportView: View {
    let state: BrowserState
    let close: () -> Void

    @State private var source: ImportSource?

    var body: some View {
        switch source {
        case .arc:
            ArcImportView(state: state, back: { source = nil }, close: close)
        case nil:
            VStack(alignment: .leading, spacing: 14) {
                Text("Bring your tabs, history, passwords and sign-ins from another browser.")
                    .foregroundStyle(.secondary)
                ForEach(ImportSource.allCases) { source in
                    Button { self.source = source } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let icon = source.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "globe") }
                            }
                            .frame(width: 32, height: 32)
                            Text(verbatim: source.name).font(.title3)
                            Spacer()
                            if !source.isAvailable {
                                Text("Not installed").foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.05)))
                    .disabled(!source.isAvailable)
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 520, height: 460)
        }
    }
}

/// Chooses which of Arc's spaces come into Flux, and where.
private struct ArcImportView: View {
    let state: BrowserState
    let back: () -> Void
    let close: () -> Void

    @State private var arcSpaces: [ArcLibrary.Space] = []
    @State private var chosen: Set<String> = []
    /// Arc's space id to a Flux space's, nil for a new space.
    @State private var destinations: [String: UUID] = [:]
    @State private var includesToday = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your Arc spaces come with their favorites, pinned tabs, folders and splits. Arc itself is left as it is.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if failed {
                Text("Arc's sidebar couldn't be read.")
                    .foregroundStyle(.red)
            }
            List {
                ForEach(arcSpaces) { space in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { chosen.contains(space.id) },
                            set: { isOn in if isOn { chosen.insert(space.id) } else { chosen.remove(space.id) } }
                        )) {
                            HStack(spacing: 6) {
                                Text(verbatim: space.icon ?? "●")
                                    .foregroundStyle(Color(hex: space.color ?? BrowserState.spaceColors[0]))
                                Text(verbatim: space.name)
                                Text("\(space.tabCount) tabs").foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                        Picker("Into", selection: Binding(
                            get: { destinations[space.id] },
                            set: { destinations[space.id] = $0 }
                        )) {
                            Text("New Space").tag(UUID?.none)
                            Divider()
                            ForEach(state.spaces) { flux in
                                Text(verbatim: flux.name).tag(UUID?.some(flux.id))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!chosen.contains(space.id))
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            Toggle("Also import Today's tabs", isOn: $includesToday)
            HStack {
                Button("Back", action: back)
                Spacer()
                Button("Cancel", role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    state.importFromArc(
                        arcSpaces.filter { chosen.contains($0.id) },
                        destinations: destinations.filter { chosen.contains($0.key) },
                        includesToday: includesToday
                    )
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
        .onAppear {
            do {
                arcSpaces = try ArcLibrary.loadSpaces()
                chosen = Set(arcSpaces.map(\.id))
            } catch {
                failed = true
            }
        }
    }
}
