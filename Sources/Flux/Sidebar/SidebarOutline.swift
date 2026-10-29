import AppKit
import SwiftUI

/// Pinned tabs with their folders, then today's tabs, in an outline view: AppKit's outline handles
/// dragging items between levels far better than SwiftUI lists.
struct SidebarOutline: NSViewRepresentable {
    let state: BrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.headerView = nil
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.rowSizeStyle = .custom
        outline.rowHeight = 30
        outline.indentationPerLevel = 14
        outline.floatsGroupRows = false
        outline.addTableColumn(NSTableColumn(identifier: .init("main")))
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.registerForDraggedTypes([Coordinator.dragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.menu = context.coordinator.contextMenu

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.outline = outline
        context.coordinator.reload()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Read here so SwiftUI calls this again when they change.
        _ = state.sidebarRevision
        _ = state.selectedSpaceID
        _ = state.selectedTab
        context.coordinator.reloadIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        static let dragType = NSPasteboard.PasteboardType("com.flux-browser.sidebar-item")

        /// Group rows. The instances stay the same so the outline keeps their state.
        final class SectionItem: NSObject {
            let section: SidebarNode.Section
            init(_ section: SidebarNode.Section) { self.section = section }
        }

        let state: BrowserState
        weak var outline: NSOutlineView?
        let contextMenu = NSMenu()
        private let sections = [SectionItem(.pinned), SectionItem(.today)]
        private var shownRevision = -1
        private var shownSpaceID: UUID?
        private var isSyncingSelection = false

        init(state: BrowserState) {
            self.state = state
            super.init()
            contextMenu.delegate = self
            contextMenu.autoenablesItems = false
        }

        func reloadIfNeeded() {
            if shownRevision != state.sidebarRevision || shownSpaceID != state.selectedSpaceID {
                reload()
            } else {
                syncSelection()
            }
        }

        func reload() {
            guard let outline else { return }
            shownRevision = state.sidebarRevision
            shownSpaceID = state.selectedSpaceID
            outline.reloadData()
            for section in sections {
                outline.expandItem(section)
            }
            expandFolders(in: nil)
            syncSelection()
        }

        private func expandFolders(in parent: Folder?) {
            for entry in state.entries(in: .pinned, parentID: parent?.id) {
                guard case .folder(let folder) = entry, folder.node.isExpanded else { continue }
                outline?.expandItem(folder)
                expandFolders(in: folder)
            }
        }

        private func syncSelection() {
            guard let outline else { return }
            isSyncingSelection = true
            defer { isSyncingSelection = false }
            if let tab = state.selectedTab {
                let row = outline.row(forItem: tab)
                if row >= 0 {
                    outline.selectRowIndexes([row], byExtendingSelection: false)
                    return
                }
            }
            outline.deselectAll(nil)
        }


        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            item is SectionItem || item is Folder
        }

        private func children(of item: Any?) -> [NSObject] {
            switch item {
            case nil:
                return sections
            case let section as SectionItem:
                return state.entries(in: section.section, parentID: nil).map(\.object)
            case let folder as Folder:
                return state.entries(in: .pinned, parentID: folder.id).map(\.object)
            default:
                return []
            }
        }


        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            item is SectionItem
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            let row: AnyView
            switch item {
            case let section as SectionItem:
                row = AnyView(SectionHeaderRow(section: section.section))
            case let tab as Tab:
                row = AnyView(TabRow(tab: tab) { [weak self] in self?.state.close(tab) })
            case let folder as Folder:
                row = AnyView(FolderRow(folder: folder) { [weak self] title in
                    self?.state.rename(folder, to: title)
                } onBeginEditing: { [weak outlineView] in
                    // The page may have the keyboard. The field needs Flux's window to be key.
                    outlineView?.window?.makeKey()
                })
            default:
                return nil
            }
            let cell = outlineView.makeView(withIdentifier: HostingCell.identifier, owner: nil) as? HostingCell ?? HostingCell()
            cell.show(row)
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            if let folder = item as? Folder {
                if outlineView.isItemExpanded(folder) {
                    outlineView.collapseItem(folder)
                } else {
                    outlineView.expandItem(folder)
                }
                return false
            }
            return item is Tab
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let outline,
                  let tab = outline.item(atRow: outline.selectedRow) as? Tab else { return }
            state.select(tab)
        }

        func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
            !(item is SectionItem)
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            if let folder = notification.userInfo?["NSObject"] as? Folder {
                state.setExpanded(folder, true)
            }
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            if let folder = notification.userInfo?["NSObject"] as? Folder {
                state.setExpanded(folder, false)
            }
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let id = (item as? Tab)?.id ?? (item as? Folder)?.id else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(id.uuidString, forType: Self.dragType)
            return pasteboardItem
        }

        func outlineView(
            _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
            proposedItem item: Any?, proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard let entry = draggedEntry(info), let target = destination(item, index: index),
                  state.canMove(entry, to: target.section, parentID: target.parentID) else { return [] }
            return .move
        }

        func outlineView(
            _ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
            item: Any?, childIndex index: Int
        ) -> Bool {
            guard let entry = draggedEntry(info), let target = destination(item, index: index) else { return false }
            return state.move(entry, to: target.section, parentID: target.parentID, index: target.index)
        }

        private func draggedEntry(_ info: NSDraggingInfo) -> BrowserState.SidebarEntry? {
            guard let string = info.draggingPasteboard.string(forType: Self.dragType),
                  let id = UUID(uuidString: string) else { return nil }
            return state.entry(id: id)
        }

        /// Where a drop lands. Dropping on a folder adds to its end. Dropping on a tab isn't a place.
        private func destination(_ item: Any?, index: Int) -> (section: SidebarNode.Section, parentID: UUID?, index: Int?)? {
            let childIndex = index == NSOutlineViewDropOnItemIndex ? nil : index
            switch item {
            case let section as SectionItem:
                return (section.section, nil, childIndex)
            case let folder as Folder:
                return (.pinned, folder.id, childIndex)
            default:
                return nil
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline else { return }
            let item = outline.clickedRow >= 0 ? outline.item(atRow: outline.clickedRow) : nil
            switch item {
            case let tab as Tab:
                menu.addItem(action(tab.isPinned ? "Unpin Tab" : "Pin Tab") { [weak self] in self?.state.togglePin(tab) })
                if tab.hasLeftPinnedURL {
                    menu.addItem(action("Go Back to Pinned Page") { tab.goBackToPinnedURL() })
                }
                menu.addItem(.separator())
                menu.addItem(action(tab.isPinned ? "Unload Tab" : "Close Tab") { [weak self] in self?.state.close(tab) })
            case let folder as Folder:
                menu.addItem(action("Rename Folder") { folder.isEditingTitle = true })
                let newFolder = action("New Folder Inside") { [weak self] in
                    self?.state.createFolder(parentID: folder.id)
                }
                newFolder.isEnabled = state.canPlace(nil, in: folder.id)
                menu.addItem(newFolder)
                menu.addItem(.separator())
                menu.addItem(action("Delete Folder") { [weak self] in self?.state.delete(folder) })
            default:
                menu.addItem(action("New Folder") { [weak self] in self?.state.createFolder() })
            }
        }

        private func action(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(ClosureTarget.run), keyEquivalent: "")
            let target = ClosureTarget(handler)
            item.target = target
            item.representedObject = target
            return item
        }
    }
}

/// Lets a menu item run a closure. The menu item keeps the target alive.
private final class ClosureTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

/// An outline cell showing a SwiftUI row.
private final class HostingCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HostingCell")
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    func show(_ view: AnyView) {
        host.rootView = view
    }
}
