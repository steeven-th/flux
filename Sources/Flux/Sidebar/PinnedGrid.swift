import AppKit
import SwiftUI

/// The selected space's pinned tabs, as tiles at the top of the sidebar. A collection view rather
/// than a SwiftUI grid, so tiles can move out of the way while something is dragged over them.
struct PinnedGrid: NSViewRepresentable {
    static let columns = 4
    static let spacing: CGFloat = 6
    static let tileHeight: CGFloat = 42
    /// Same identifier as the sidebar outline's drag type, so items move between the two.
    static let dragType = NSPasteboard.PasteboardType("com.flux-browser.sidebar-item")

    let state: BrowserState

    /// Height for the current number of tiles. Kept a few points tall when empty so tabs can be
    /// dropped there.
    static func height(for count: Int) -> CGFloat {
        guard count > 0 else { return 8 }
        let rows = CGFloat((count + columns - 1) / columns)
        return rows * tileHeight + (rows - 1) * spacing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> NSCollectionView {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Self.spacing
        layout.minimumLineSpacing = Self.spacing

        let collection = PinnedCollectionView()
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        collection.register(PinnedItem.self, forItemWithIdentifier: PinnedItem.identifier)
        collection.register(
            NoGapIndicator.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindInterItemGapIndicator,
            withIdentifier: NoGapIndicator.identifier
        )
        collection.registerForDraggedTypes([Self.dragType])
        collection.setDraggingSourceOperationMask(.move, forLocal: true)
        collection.dragExitHandler = { [weak coordinator = context.coordinator] in coordinator?.endPreview() }
        collection.menuProvider = { [weak coordinator = context.coordinator] index in coordinator?.menu(for: index) }
        context.coordinator.collection = collection
        return collection
    }

    func updateNSView(_ collection: NSCollectionView, context: Context) {
        _ = state.sidebarRevision
        _ = state.selectedSpaceID
        _ = state.selectedTab
        context.coordinator.reload()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        let state: BrowserState
        weak var collection: NSCollectionView?
        /// What the grid shows. While something is dragged over it, tiles are already moved to where
        /// they would end up, and a nil slot stands for an item dragged in from the outline.
        private var tiles: [Tab?] = []
        private var isPreviewing = false
        /// A tile dragged within the grid shows as an empty slot while it moves.
        private var draggedTabID: UUID?
        /// Moves started while another one animates are skipped: overlapping moves left tiles
        /// showing the wrong content. The latest proposal is applied once the animation ends.
        private var isAnimating = false
        private var pendingProposal: (entry: BrowserState.SidebarEntry, index: Int)?

        init(state: BrowserState) {
            self.state = state
        }

        func reload() {
            guard !isPreviewing else { return }
            tiles = state.pinnedTabs
            collection?.reloadData()
        }

        func endPreview() {
            isPreviewing = false
            draggedTabID = nil
            pendingProposal = nil
            reload()
        }

        private func configure(_ item: NSCollectionViewItem, at index: Int) {
            guard let item = item as? PinnedItem, tiles.indices.contains(index) else { return }
            if let tab = tiles[index], tab.id != draggedTabID {
                item.show(AnyView(PinnedTile(tab: tab, isSelected: state.selectedTab === tab)))
            } else {
                item.show(AnyView(DropSlot()))
            }
        }

        private func refreshVisibleItems() {
            guard let collection else { return }
            for indexPath in collection.indexPathsForVisibleItems() {
                if let item = collection.item(at: indexPath) {
                    configure(item, at: indexPath.item)
                }
            }
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            tiles.count
        }

        func collectionView(
            _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: PinnedItem.identifier, for: indexPath)
            configure(item, at: indexPath.item)
            return item
        }

        // The empty slot already shows where the drop lands.
        func collectionView(
            _ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
            at indexPath: IndexPath
        ) -> NSView {
            collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: NoGapIndicator.identifier, for: indexPath)
        }

        func collectionView(
            _ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> NSSize {
            let width = (collectionView.bounds.width - PinnedGrid.spacing * CGFloat(PinnedGrid.columns - 1))
                / CGFloat(PinnedGrid.columns)
            return NSSize(width: max(floor(width), 1), height: PinnedGrid.tileHeight)
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            if let index = indexPaths.first?.item, let tab = tiles[safe: index] ?? nil {
                state.select(tab)
            }
            collectionView.deselectAll(nil)
        }

        func collectionView(
            _ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath
        ) -> NSPasteboardWriting? {
            guard let tab = tiles[indexPath.item] else { return nil }
            let item = NSPasteboardItem()
            item.setString(tab.id.uuidString, forType: PinnedGrid.dragType)
            return item
        }

        func collectionView(
            _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation
        ) {
            endPreview()
        }

        func collectionView(
            _ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
            proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
            dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
        ) -> NSDragOperation {
            guard let entry = draggedEntry(draggingInfo), state.canMove(entry, to: .pinned, parentID: nil) else {
                return []
            }
            dropOperation.pointee = .before
            preview(entry, at: proposedIndexPath.pointee.item)
            return .move
        }

        /// Moves the dragged tile, or an empty slot for an item from the outline, to where it would
        /// land, so the other tiles make room for it.
        private func preview(_ entry: BrowserState.SidebarEntry, at proposed: Int) {
            guard let collection else { return }
            guard !isAnimating else {
                pendingProposal = (entry, proposed)
                return
            }
            isPreviewing = true
            let current = tiles.firstIndex { $0?.id == entry.id } ?? tiles.firstIndex { $0 == nil }
            if let current, tiles[current] != nil, draggedTabID == nil {
                draggedTabID = entry.id
                refreshVisibleItems()
            }
            animate { [self] in
                guard let current else {
                    let target = min(proposed, tiles.count)
                    tiles.insert(nil, at: target)
                    collection.animator().insertItems(at: [IndexPath(item: target, section: 0)])
                    return true
                }
                // Dropping before the tile itself or before the next one leaves it in place.
                let target = min(proposed > current ? proposed - 1 : proposed, tiles.count - 1)
                guard target != current else { return false }
                let tile = tiles.remove(at: current)
                tiles.insert(tile, at: target)
                collection.animator().moveItem(
                    at: IndexPath(item: current, section: 0), to: IndexPath(item: target, section: 0)
                )
                return true
            }
        }

        /// Runs a change that returns whether it animated anything, then puts every visible tile's
        /// content back in step and applies the proposal that came in meanwhile.
        private func animate(_ change: @escaping () -> Bool) {
            isAnimating = true
            var changed = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                changed = change()
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isAnimating = false
                    if changed { self.refreshVisibleItems() }
                    if self.isPreviewing, let pending = self.pendingProposal {
                        self.pendingProposal = nil
                        self.preview(pending.entry, at: pending.index)
                    }
                }
            }
        }

        func collectionView(
            _ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
            indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation
        ) -> Bool {
            guard let entry = draggedEntry(draggingInfo) else { return false }
            // The preview already holds the tile, or an empty slot, where it lands.
            let index = tiles.firstIndex { $0?.id == entry.id } ?? tiles.firstIndex { $0 == nil }
            isPreviewing = false
            draggedTabID = nil
            pendingProposal = nil
            let moved = state.move(entry, to: .pinned, parentID: nil, index: index)
            reload()
            return moved
        }

        private func draggedEntry(_ info: NSDraggingInfo) -> BrowserState.SidebarEntry? {
            guard let string = info.draggingPasteboard.string(forType: PinnedGrid.dragType),
                  let id = UUID(uuidString: string) else { return nil }
            return state.entry(id: id)
        }

        func menu(for index: Int) -> NSMenu? {
            guard let tab = tiles[safe: index] ?? nil else { return nil }
            let menu = NSMenu()
            menu.autoenablesItems = false
            if tab.hasLeftOriginalURL {
                menu.addItem(MenuAction.item("Go Back to Original Page") { tab.goBackToOriginalURL() })
            }
            menu.addItem(MenuAction.item("Unload") { [weak self] in self?.state.close(tab) })
            menu.addItem(.separator())
            let unpin = NSMenuItem(title: "Unpin", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(MenuAction.item("Move to Favorites") { [weak self] in self?.state.moveToFavorites(tab) })
            submenu.addItem(MenuAction.item("Move to Today") { [weak self] in self?.state.moveToToday(tab) })
            submenu.addItem(.separator())
            submenu.addItem(MenuAction.item("Close Tab…") { [weak self] in
                guard let self, TabRemovalConfirmation.confirm(tab, state: self.state) else { return }
                self.state.remove(tab)
            })
            unpin.submenu = submenu
            menu.addItem(unpin)
            return menu
        }
    }
}

/// Builds its context menu for the tile under the click.
private final class PinnedCollectionView: NSCollectionView {
    var menuProvider: ((Int) -> NSMenu?)?
    /// The delegate isn't told when a drag leaves the grid, so the preview is undone from here.
    var dragExitHandler: (() -> Void)?

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        dragExitHandler?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = indexPathForItem(at: point)?.item else { return nil }
        return menuProvider?(index)
    }
}

private final class PinnedItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PinnedItem")
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    override func loadView() {
        view = ClickThroughView()
        host.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func show(_ view: AnyView) {
        host.rootView = view
    }
}

/// Keeps clicks away from the SwiftUI tile, so the collection view handles selection and dragging.
private final class ClickThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }
}

private final class NoGapIndicator: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("NoGapIndicator")
}

/// Where a dragged item will land.
private struct DropSlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct PinnedTile: View {
    let tab: Tab
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Group {
            if let favicon = tab.favicon {
                Image(nsImage: favicon).resizable().interpolation(.high)
            } else {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .opacity(tab.isLoaded ? 1 : 0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Color.primary.opacity(isSelected ? 0.14 : 0.06)))
        .overlay(shape.strokeBorder(Color.primary.opacity(isSelected ? 0.25 : 0.12), lineWidth: 1))
        .help(tab.displayTitle)
    }
}
