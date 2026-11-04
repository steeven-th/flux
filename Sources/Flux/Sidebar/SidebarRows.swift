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

struct SidebarDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 1)
    }
}

struct NewTabRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16, height: 16)
            Text("New Tab")
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

/// A loaded tab shows a button that unloads it. Once unloaded, the button closes it. The tab
/// heading a group shows the group's cross instead, while the group is under the mouse.
struct TabRow: View {
    let tab: Tab
    var onUnload: () -> Void = {}
    var onClose: () -> Void = {}
    var groupHover: GroupHover?
    var onCloseGroup: (() -> Void)?

    @State private var isHovered = false

    init(tab: Tab, onUnload: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.tab = tab
        self.onUnload = onUnload
        self.onClose = onClose
    }

    init(tab: Tab, groupHover: GroupHover, onCloseGroup: @escaping () -> Void) {
        self.tab = tab
        self.groupHover = groupHover
        self.onCloseGroup = onCloseGroup
    }

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

            // Before the title, so the buttons shown on hover don't move it.
            AudioButton(tab: tab)

            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                // Arc dims tabs whose page isn't loaded.
                .opacity(tab.isLoaded ? 1 : 0.6)

            Spacer(minLength: 0)

            if let onCloseGroup {
                if groupHover?.headID == tab.id {
                    Button(action: onCloseGroup) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Close Group")
                }
            } else if isHovered {
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
            FolderIcon(openness: folder.isExpanded ? 1 : 0)
                .stroke(.secondary, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                .frame(width: 16, height: 16)
                .animation(.easeInOut(duration: 0.2), value: folder.isExpanded)
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

/// SF Symbols has no open folder. When open, the front flap tilts forward, away from the back.
struct FolderIcon: Shape {
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let flapTop = 0.4 + 0.14 * openness
        var path = Path()
        path.addLines([
            point(0.06, 0.86), point(0.06, 0.18), point(0.38, 0.18), point(0.46, 0.28),
            point(0.94, 0.28), point(0.94, flapTop),
        ])
        path.addLines([
            point(0.06 + 0.16 * openness, flapTop), point(0.94 + 0.06 * openness, flapTop),
            point(0.94, 0.86), point(0.06, 0.86),
        ])
        path.closeSubpath()
        return path
    }
}

/// A split's tabs side by side, the one shown in the focused pane marked.
struct SplitRow: View {
    let state: BrowserState
    let split: Split
    let onClose: (Tab) -> Void

    var body: some View {
        let panes = state.panes(of: split)
        HStack(spacing: 0) {
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    Rectangle().fill(.primary.opacity(0.15)).frame(width: 1, height: 14)
                }
                SplitPaneItem(tab: tab, isFocused: tab === state.selectedTab) { onClose(tab) }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity)
    }
}

private struct SplitPaneItem: View {
    let tab: Tab
    let isFocused: Bool
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let favicon = tab.favicon {
                    Image(nsImage: favicon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 14, height: 14)
            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(tab.isLoaded ? 1 : 0.6)
            Spacer(minLength: 0)
            if isHovered {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
        }
        .padding(.horizontal, 5)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 5).fill(.primary.opacity(isFocused ? 0.08 : 0)).padding(.vertical, 3))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

/// Shows that a tab plays sound, or is muted, and mutes it or turns its sound back on, as in Arc.
struct AudioButton: View {
    let tab: Tab

    var body: some View {
        if tab.isPlayingAudio || tab.isMuted {
            Button(action: tab.toggleMute) {
                Image(systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(tab.isMuted ? "Unmute Tab" : "Mute Tab")
        }
    }
}
