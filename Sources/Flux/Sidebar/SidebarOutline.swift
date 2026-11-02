import AppKit
import SwiftUI

/// Favorites with their folders, then today's tabs, in an outline view: AppKit's outline handles
/// dragging items between levels far better than SwiftUI lists.
struct SidebarOutline: NSViewRepresentable {
    let state: BrowserState
    let onNewTab: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onNewTab: onNewTab)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = SidebarOutlineView()
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
        outline.target = context.coordinator
        outline.action = #selector(Coordinator.clickRow)
        outline.middleClickHandler = { [weak coordinator = context.coordinator] item in
            if let tab = item as? Tab { coordinator?.state.close(tab) }
        }
        outline.groupClickHandler = { [weak coordinator = context.coordinator] item in
            coordinator?.toggle(item)
        }

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

        /// The line between favorites and today, and the first row of today.
        final class SeparatorItem: NSObject {}
        final class NewTabItem: NSObject {}

        let state: BrowserState
        let onNewTab: () -> Void
        weak var outline: NSOutlineView?
        let contextMenu = NSMenu()
        private let sections = [SectionItem(.favorites), SectionItem(.today)]
        private let separator = SeparatorItem()
        private let newTab = NewTabItem()
        private var shownRevision = -1
        private var shownSpaceID: UUID?
        private var isSyncingSelection = false

        init(state: BrowserState, onNewTab: @escaping () -> Void) {
            self.state = state
            self.onNewTab = onNewTab
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
            for section in sections where !state.isCollapsed(section.section) {
                outline.expandItem(section)
            }
            expandFolders(in: nil)
            syncSelection()
        }

        private func expandFolders(in parent: Folder?) {
            for entry in state.entries(in: .favorites, parentID: parent?.id) {
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
                let row = outline.row(forItem: state.split(of: tab) ?? tab)
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
                return [sections[0], separator, sections[1]]
            case let section as SectionItem:
                let entries = state.entries(in: section.section, parentID: nil).map(\.object)
                return section.section == .today ? [newTab] + entries : entries
            case let folder as Folder:
                return state.entries(in: .favorites, parentID: folder.id).map(\.object)
            default:
                return []
            }
        }


        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            item is SectionItem
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            switch item {
            case is SectionItem: nil
            case is SeparatorItem: SeparatorRowView()
            default: HoverRowView()
            }
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            item is SeparatorItem ? 17 : outlineView.rowHeight
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            let row: AnyView
            switch item {
            case let section as SectionItem:
                row = AnyView(SectionHeaderRow(section: section.section))
            case is NewTabItem:
                row = AnyView(NewTabRow())
            case let tab as Tab:
                row = AnyView(TabRow(tab: tab) { [weak self] in
                    self?.state.unload(tab)
                } onClose: { [weak self] in
                    guard let self else { return }
                    if tab.isKept {
                        guard TabRemovalConfirmation.confirm(tab, state: self.state) else { return }
                        self.state.remove(tab)
                    } else {
                        self.state.close(tab)
                    }
                })
            case let split as Split:
                row = AnyView(SplitRow(state: state, split: split) { [weak self] tab in
                    self?.state.closePane(tab)
                })
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
            item is Tab || item is Split
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let outline else { return }
            switch outline.item(atRow: outline.selectedRow) {
            case let tab as Tab:
                // ⌥-click puts the tab in a split with the one shown, like in Arc.
                if NSApp.currentEvent?.modifierFlags.contains(.option) == true, state.canSplit(with: tab) {
                    state.addToSplit(tab)
                } else {
                    state.select(tab)
                }
            case let split as Split:
                if let pane = pane(of: split, clickedIn: outline, row: outline.selectedRow) { state.select(pane) }
            default:
                break
            }
        }

        /// Rows that select nothing act here, once the click ends: the outline may ask
        /// shouldSelectItem more than once for the same click. A click on a split already
        /// selected changes no selection either, but may pick another pane.
        @objc func clickRow() {
            guard let outline, outline.clickedRow >= 0 else { return }
            let row = outline.clickedRow
            switch outline.item(atRow: row) {
            case let folder as Folder:
                // The disclosure arrow already expanded or collapsed the folder.
                if let event = NSApp.currentEvent,
                   outline.frameOfOutlineCell(atRow: row).contains(outline.convert(event.locationInWindow, from: nil)) {
                    return
                }
                toggle(folder)
            case is NewTabItem:
                onNewTab()
            case let split as Split:
                if let pane = pane(of: split, clickedIn: outline, row: row) { state.select(pane) }
            default:
                break
            }
        }

        func toggle(_ item: Any) {
            guard let outline else { return }
            if outline.isItemExpanded(item) {
                outline.animator().collapseItem(item)
            } else {
                outline.animator().expandItem(item)
            }
        }

        /// Panes share the row's width equally.
        private func pane(of split: Split, clickedIn outline: NSOutlineView, row: Int) -> Tab? {
            let panes = state.panes(of: split)
            guard !panes.isEmpty, let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseUp else {
                return panes.first { $0 === state.selectedTab } ?? panes.first
            }
            let cell = outline.frameOfCell(atColumn: 0, row: row)
            let x = outline.convert(event.locationInWindow, from: nil).x - cell.minX
            let index = Int(x / (cell.width / CGFloat(panes.count)))
            return panes[min(max(index, 0), panes.count - 1)]
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            setExpanded(notification.userInfo?["NSObject"], true)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            setExpanded(notification.userInfo?["NSObject"], false)
        }

        private func setExpanded(_ item: Any?, _ isExpanded: Bool) {
            switch item {
            case let folder as Folder:
                state.setExpanded(folder, isExpanded)
            case let section as SectionItem:
                state.setCollapsed(section.section, !isExpanded)
            default:
                break
            }
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let id = (item as? Tab)?.id ?? (item as? Folder)?.id ?? (item as? Split)?.id else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(id.uuidString, forType: Self.dragType)
            return pasteboardItem
        }

        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
            state.draggedTab = draggedItems.first as? Tab
        }

        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            state.draggedTab = nil
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
                // Today starts with the new tab row, which isn't one of its entries.
                let offset = section.section == .today ? 1 : 0
                return (section.section, nil, childIndex.map { max($0 - offset, 0) })
            case let folder as Folder:
                return (.favorites, folder.id, childIndex)
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
                let pin = MenuAction.item("Pin Tab") { [weak self] in self?.state.pin(tab) }
                pin.isEnabled = state.canMove(.tab(tab), to: .pinned, parentID: nil)
                menu.addItem(pin)
                if tab.node.section == .today {
                    menu.addItem(MenuAction.item("Add to Favorites") { [weak self] in self?.state.moveToFavorites(tab) })
                } else {
                    menu.addItem(MenuAction.item("Move to Today") { [weak self] in self?.state.moveToToday(tab) })
                }
                if tab.hasLeftOriginalURL {
                    menu.addItem(MenuAction.item("Go Back to Original Page") { tab.goBackToOriginalURL() })
                }
                let split = MenuAction.item("Open in Split View") { [weak self] in self?.state.addToSplit(tab) }
                split.isEnabled = state.canSplit(with: tab)
                menu.addItem(split)
                menu.addItem(.separator())
                if tab.isKept {
                    menu.addItem(MenuAction.item("Unload Tab") { [weak self] in self?.state.close(tab) })
                    menu.addItem(MenuAction.item("Remove from Favorites…") { [weak self] in
                        guard let self, TabRemovalConfirmation.confirm(tab, state: self.state) else { return }
                        self.state.remove(tab)
                    })
                } else {
                    if tab.isLoaded {
                        menu.addItem(MenuAction.item("Unload Tab") { [weak self] in self?.state.unload(tab) })
                    }
                    menu.addItem(MenuAction.item("Close Tab") { [weak self] in self?.state.close(tab) })
                }
            case let split as Split:
                menu.addItem(MenuAction.item("Separate Tabs") { [weak self] in self?.state.separate(split) })
                menu.addItem(MenuAction.item(split.isVertical ? "Convert to Horizontal Split View" : "Convert to Vertical Split View") { [weak self] in
                    self?.state.toggleOrientation(split)
                })
            case let folder as Folder:
                menu.addItem(MenuAction.item("Rename Folder") { folder.isEditingTitle = true })
                let newFolder = MenuAction.item("New Folder Inside") { [weak self] in
                    self?.state.createFolder(parentID: folder.id)
                }
                newFolder.isEnabled = state.canPlace(nil, in: folder.id)
                menu.addItem(newFolder)
                menu.addItem(.separator())
                menu.addItem(MenuAction.item("Delete Folder") { [weak self] in self?.state.delete(folder) })
            default:
                menu.addItem(MenuAction.item("New Folder") { [weak self] in self?.state.createFolder() })
            }
        }
    }
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

/// A middle click closes the tab under it, like in other browsers. Group rows send no action
/// when clicked, so a click on a section's title is handled here.
private final class SidebarOutlineView: NSOutlineView {
    var middleClickHandler: ((Any) -> Void)?
    var groupClickHandler: ((Any) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if !event.modifierFlags.contains(.control), row >= 0, let item = item(atRow: row), isGroupItem(item) {
            groupClickHandler?(item)
            return
        }
        super.mouseDown(with: event)
    }

    private func isGroupItem(_ item: Any) -> Bool {
        delegate?.outlineView?(self, isGroupItem: item) ?? false
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseUp(with: event) }
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, let item = item(atRow: row) { middleClickHandler?(item) }
    }
}

/// Drawn by the row rather than a cell, so the line spans the sidebar like the one under the pinned
/// tabs instead of starting at the outline's indentation.
private final class SeparatorRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSRect(x: bounds.minX, y: bounds.midY.rounded(.down), width: bounds.width, height: 1).fill()
    }
}

/// Shows a background under the mouse, where the selection would show. The page window usually has
/// the keyboard, so the row follows the mouse whichever window is key.
private final class HoverRowView: NSTableRowView {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isHovered, !isSelected else { return }
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 0), xRadius: 6, yRadius: 6).fill()
    }
}
