import SwiftUI

/// A site asking to use something, under the address, in place of Chromium's own prompt.
struct PermissionPrompt: View {
    let request: FLXPermissionRequest
    let onAnswer: (Bool?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(site) wants to")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button { onAnswer(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.items(for: request.permissions), id: \.text) { item in
                    Label(item.text, systemImage: item.symbol)
                }
            }

            HStack {
                Spacer()
                Button("Block") { onAnswer(false) }
                Button("Allow") { onAnswer(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var site: String {
        URL(string: request.origin)?.host() ?? request.origin
    }

    private static func items(for permissions: FLXPermission) -> [(symbol: String, text: String)] {
        let known: [(FLXPermission, String, String)] = [
            (.notifications, "bell", String(localized: "Show notifications")),
            (.geolocation, "location", String(localized: "Know your location")),
            (.camera, "video", String(localized: "Use your camera")),
            (.cameraPanTiltZoom, "video", String(localized: "Move your camera")),
            (.microphone, "mic", String(localized: "Use your microphone")),
            (.clipboard, "doc.on.clipboard", String(localized: "See text and images you copy")),
            (.multipleDownloads, "arrow.down.circle", String(localized: "Download several files")),
            (.MIDI, "pianokeys", String(localized: "Use your MIDI devices")),
            (.windowManagement, "macwindow.on.rectangle", String(localized: "Manage windows on all your displays")),
            (.localFonts, "textformat", String(localized: "Use the fonts on your Mac")),
            (.idleDetection, "person.crop.circle.badge.clock", String(localized: "Know when you're using your Mac")),
            (.fileSystem, "folder", String(localized: "Edit files on your Mac")),
            (.localNetwork, "network", String(localized: "Use devices on your local network")),
            (.protocolHandler, "link", String(localized: "Open links of some types")),
            (.sensors, "gyroscope", String(localized: "Use your motion sensors")),
            (.keyboardLock, "keyboard", String(localized: "Use your keyboard shortcuts")),
            (.pointerLock, "cursorarrow", String(localized: "Lock and use your pointer")),
            (.storageAccess, "externaldrive", String(localized: "Use cookies and site data")),
            (.topLevelStorageAccess, "externaldrive", String(localized: "Use cookies and site data")),
        ]
        var items: [(symbol: String, text: String)] = []
        for (permission, symbol, text) in known where !permissions.intersection(permission).isEmpty {
            if !items.contains(where: { $0.text == text }) { items.append((symbol, text)) }
        }
        let covered = known.reduce(FLXPermission()) { $0.union($1.0) }
        if items.isEmpty || !permissions.subtracting(covered).isEmpty {
            items.append(("questionmark.circle", String(localized: "Use other features of your Mac")))
        }
        return items
    }
}
