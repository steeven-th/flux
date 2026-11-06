import SwiftUI
import UniformTypeIdentifiers

/// What every file of the library offers: open on click, drag to another app, and a menu like the
/// Finder's.
struct FileActions: ViewModifier {
    let url: URL
    var onOpen: (() -> Void)?
    /// Takes the file out of the library without touching it. Also called once it is in the Trash.
    var onHide: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() ?? open() }
            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            .contextMenu {
                if isImage {
                    Button("Copy Image", action: copyImage)
                } else {
                    Button("Copy", action: copy)
                }
                Divider()
                Button("Send with Messages") { share(.composeMessage) }
                Button("AirDrop") { share(.sendViaAirDrop) }
                Divider()
                Button(openTitle, action: open)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Divider()
                if let onHide {
                    Button("Hide from Flux", action: onHide)
                }
                Button("Move to Trash", action: moveToTrash)
            }
    }

    private var isImage: Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    /// "Open in Preview", after the app that opens the file.
    private var openTitle: String {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return String(localized: "Open") }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        return String(localized: "Open in \(name)")
    }

    private func open() {
        NSWorkspace.shared.open(url)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    /// The image itself, for apps that paste pictures, and the file, for those that take files.
    private func copyImage() {
        NSPasteboard.general.clearContents()
        var objects: [NSPasteboardWriting] = [url as NSURL]
        if let image = NSImage(contentsOf: url) { objects.insert(image, at: 0) }
        NSPasteboard.general.writeObjects(objects)
    }

    private func share(_ service: NSSharingService.Name) {
        NSSharingService(named: service)?.perform(withItems: [url])
    }

    private func moveToTrash() {
        FileRemoval.moveToTrash(url, onHide: onHide)
    }
}

/// Removing a file from the latest files: hidden from Flux only, or put in the Trash as well.
@MainActor
enum FileRemoval {
    static func confirm(_ url: URL, onHide: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove “\(url.lastPathComponent)”?")
        alert.informativeText = String(localized: "Hidden from Flux, the file stays on your Mac. Moved to the Trash, it is gone from both.")
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Hide from Flux"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: moveToTrash(url, onHide: onHide)
        case .alertSecondButtonReturn: onHide()
        default: break
        }
    }

    static func moveToTrash(_ url: URL, onHide: (() -> Void)?) {
        guard (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil else { return }
        onHide?()
    }
}

extension View {
    func fileActions(_ url: URL, onOpen: (() -> Void)? = nil, onHide: (() -> Void)? = nil) -> some View {
        modifier(FileActions(url: url, onOpen: onOpen, onHide: onHide))
    }
}

extension DownloadRecord {
    var fileURL: URL { URL(filePath: path) }

    /// "PDF · ovh.net"
    var details: String {
        let type = UTType(mimeType: mimeType) ?? UTType(filenameExtension: fileURL.pathExtension)
        let host = URL(string: url)?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        return [type?.localizedDescription, host].compactMap { $0 }.joined(separator: " · ")
    }
}
