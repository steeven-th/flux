import SwiftUI

struct SectionHeaderRow: View {
    let section: SidebarNode.Section

    var body: some View {
        (section == .favorites ? Text("Favorites") : Text("Today"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A loaded tab shows a button that unloads it. Once unloaded, the button closes it.
struct TabRow: View {
    let tab: Tab
    let onUnload: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let favicon = tab.favicon {
                    Image(nsImage: favicon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)

            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                // Arc dims tabs whose page isn't loaded.
                .opacity(tab.isLoaded ? 1 : 0.6)

            Spacer(minLength: 0)

            if isHovered {
                Button(action: tab.isLoaded ? onUnload : onClose) {
                    Image(systemName: tab.isLoaded ? "minus" : "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(tab.isLoaded ? String(localized: "Unload") : String(localized: "Close"))
            }
        }
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct FolderRow: View {
    let folder: Folder
    let onRename: (String) -> Void
    let onBeginEditing: () -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            if folder.isEditingTitle {
                TextField("Folder name", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { onRename(draft) }
                    .onAppear {
                        draft = folder.title
                        onBeginEditing()
                        isFocused = true
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { onRename(draft) }
                    }
                    // Clicking the page leaves the field focused in a window that is no longer
                    // key, so the edit ends when Flux's window loses the keyboard.
                    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                        if folder.isEditingTitle { onRename(draft) }
                    }
            } else {
                Text(folder.title).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
