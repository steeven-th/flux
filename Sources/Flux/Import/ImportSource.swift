import AppKit

/// The browsers Flux imports from. All are Chromium underneath, so history, passwords, sign-ins
/// and extensions come the same way: only their sidebars differ.
enum ImportSource: CaseIterable, Identifiable {
    case arc, dia

    var id: Self { self }

    var name: String {
        switch self {
        case .arc: "Arc"
        case .dia: "Dia"
        }
    }

    private var bundleIdentifier: String {
        switch self {
        case .arc: "company.thebrowser.Browser"
        case .dia: "company.thebrowser.dia"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .arc: ArcLibrary.isInstalled
        case .dia: DiaLibrary.isInstalled
        }
    }

    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func loadSpaces() throws -> [ImportedSpace] {
        switch self {
        case .arc: try ArcLibrary.loadSpaces()
        case .dia: try DiaLibrary.loadSpaces()
        }
    }

    /// The space the browser showed last, which Flux shows once the import is done.
    var lastSpaceID: String? {
        switch self {
        case .arc: ArcLibrary.lastSpaceID
        case .dia: DiaLibrary.lastSpaceID
        }
    }

    /// Where Chromium keeps the key of this browser's passwords and cookies.
    var keychainItem: (service: String, account: String) {
        switch self {
        case .arc: ("Arc Safe Storage", "Arc")
        case .dia: ("Dia Safe Storage", "Dia")
        }
    }

    /// Dia keeps its open tabs in a database of its own that is encrypted.
    var hasToday: Bool {
        self == .arc
    }

    /// The sources installed on this Mac, with their spaces.
    static func available() -> [(source: ImportSource, spaces: [ImportedSpace])] {
        allCases.filter(\.isAvailable).compactMap { source in
            guard let spaces = try? source.loadSpaces(), !spaces.isEmpty else { return nil }
            return (source, spaces)
        }
    }
}

enum ImportError: Error {
    case unreadable
}
