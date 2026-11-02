import AppKit
import SwiftUI

/// The selected space's pinned tabs, as tiles at the top of the sidebar. A collection view rather
/// than a SwiftUI grid, so tiles can move out of the way while something is dragged over them.
struct PinnedGrid: NSViewRepresentable {
    static let spacing: CGFloat = 6
    static let tileHeight: CGFloat = 42
    /// Same identifier as the sidebar outline's drag type, so items move between the two.
    static let dragType = NSPasteboard.PasteboardType("com.flux-browser.sidebar-item")

    let state: BrowserState
    /// The grid's width, given by the sidebar. The collection view sizes itself to its content, so
    /// its own width can't be used to size the tiles.
    let width: CGFloat

    static let minimumTileWidth: CGFloat = 44

    /// Six, four or three tiles a row, whatever fits, so twelve tiles always make full rows. With
    /// fewer tiles than that, they share the first row's whole width, and the other rows keep the
    /// same tile size.
    static func columns(for count: Int, width: CGFloat) -> Int {
        let fitting = [6, 4, 3].first { (columns: Int) -> Bool in
            let count = CGFloat(columns)
            return count * minimumTileWidth + (count - 1) * spacing <= width
        } ?? 3
        return max(min(count, fitting), 1)
    }

    /// Height for the current number of tiles. Kept a few points tall when empty so tabs can be
    /// dropped there.
    static func height(for count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return 8 }
        let columns = columns(for: count, width: width)
        let rows = CGFloat((count + columns - 1) / columns)
        return rows * tileHeight + (rows - 1) * spacing
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeNSView(context: Context) -> NSCollectionView {
        let collection = PinnedCollectionView()
        collection.collectionViewLayout = PinnedGridLayout()
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
        collection.middleClickHandler = { [weak coordinator = context.coordinator] index in coordinator?.unloadTab(at: index) }
        collection.speakerClickHandler = { [weak coordinator = context.coordinator] index in
            coordinator?.toggleMute(at: index) ?? false
        }
        context.coordinator.collection = collection
        return collection
    }

    func updateNSView(_ collection: NSCollectionView, context: Context) {
        _ = state.sidebarRevision
        _ = state.selectedSpaceID
        _ = state.selectedTab
        (collection.collectionViewLayout as? PinnedGridLayout)?.width = width
        context.coordinator.reload()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
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
                item.show(AnyView(PinnedTile(tab: tab, isSelected: state.selectedTab === tab, hover: item.hover)))
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

        /// False when the tile shows no speaker, so the click selects it.
        func toggleMute(at index: Int) -> Bool {
            guard let tab = tiles[safe: index] ?? nil, tab.isPlayingAudio || tab.isMuted else { return false }
            tab.toggleMute()
            return true
        }

        func unloadTab(at index: Int) {
            guard let tab = tiles[safe: index] ?? nil else { return }
            state.close(tab)
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
            let unpin = NSMenuItem(title: String(localized: "Unpin"), action: nil, keyEquivalent: "")
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

/// Places tile n at row n / columns, column n % columns. A flow layout wraps rows by itself, and at
/// some widths it put fewer tiles on a row than the grid has columns, which left holes.
private final class PinnedGridLayout: NSCollectionViewLayout {
    var width: CGFloat = 0 {
        didSet { if width != oldValue { invalidateLayout() } }
    }
    private var count = 0
    private var columns = 1
    private var tileWidth: CGFloat = 1

    override func prepare() {
        super.prepare()
        count = collectionView?.numberOfItems(inSection: 0) ?? 0
        columns = PinnedGrid.columns(for: count, width: width)
        tileWidth = max(floor((width - PinnedGrid.spacing * CGFloat(columns - 1)) / CGFloat(columns)), 1)
    }

    private func frame(at index: Int) -> NSRect {
        NSRect(
            x: CGFloat(index % columns) * (tileWidth + PinnedGrid.spacing),
            y: CGFloat(index / columns) * (PinnedGrid.tileHeight + PinnedGrid.spacing),
            width: tileWidth, height: PinnedGrid.tileHeight
        )
    }

    override var collectionViewContentSize: NSSize {
        NSSize(width: width, height: count == 0 ? 0 : frame(at: count - 1).maxY)
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        (0..<count).filter { frame(at: $0).intersects(rect) }.compactMap {
            layoutAttributesForItem(at: IndexPath(item: $0, section: 0))
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < count else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = frame(at: indexPath.item)
        return attributes
    }

    /// Drops land before the tile under the pointer, or after it past its middle.
    override func layoutAttributesForDropTarget(at point: NSPoint) -> NSCollectionViewLayoutAttributes? {
        let column = min(max(Int(point.x / (tileWidth + PinnedGrid.spacing)), 0), columns - 1)
        let row = max(Int(point.y / (PinnedGrid.tileHeight + PinnedGrid.spacing)), 0)
        var index = row * columns + column
        if point.x > frame(at: index).midX { index += 1 }
        return layoutAttributesForInterItemGap(before: IndexPath(item: min(index, count), section: 0))
    }

    override func layoutAttributesForInterItemGap(before indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        let attributes = NSCollectionViewLayoutAttributes(forInterItemGapBefore: indexPath)
        let tile = frame(at: indexPath.item)
        attributes.frame = NSRect(x: tile.minX - PinnedGrid.spacing, y: tile.minY, width: PinnedGrid.spacing, height: tile.height)
        return attributes
    }
}

/// Builds its context menu for the tile under the click. A middle click unloads the tile's tab, and
/// a click on a tile's speaker mutes it or turns its sound back on.
private final class PinnedCollectionView: NSCollectionView {
    var menuProvider: ((Int) -> NSMenu?)?
    var middleClickHandler: ((Int) -> Void)?
    /// Returns whether the tile had a speaker to click.
    var speakerClickHandler: ((Int) -> Bool)?
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

    /// The speaker sits in the tile's top right corner.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point), let frame = item(at: indexPath)?.view.frame {
            let speaker = NSRect(x: frame.maxX - 20, y: isFlipped ? frame.minY : frame.maxY - 20, width: 20, height: 20)
            if speaker.contains(point), speakerClickHandler?(indexPath.item) == true { return }
        }
        super.mouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseUp(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        if let index = indexPathForItem(at: point)?.item { middleClickHandler?(index) }
    }
}

private final class PinnedItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PinnedItem")
    let hover = TileHover()
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    override func loadView() {
        let view = ClickThroughView()
        view.hover = hover
        self.view = view
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

@MainActor
@Observable
final class TileHover {
    var isHovered = false
}

/// Keeps clicks away from the SwiftUI tile, so the collection view handles selection and dragging.
/// It also follows the mouse for the tile, whichever window is key, as the outline's rows do.
private final class ClickThroughView: NSView {
    var hover: TileHover?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hover?.isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hover?.isHovered = false
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
    let hover: TileHover

    private var fillOpacity: Double {
        isSelected ? 0.14 : hover.isHovered ? 0.1 : 0.06
    }

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
        .background(shape.fill(Color.primary.opacity(fillOpacity)))
        .overlay(shape.strokeBorder(Color.primary.opacity(isSelected ? 0.25 : 0.12), lineWidth: 1))
        .overlay(alignment: .topTrailing) { AudioButton(tab: tab) }
        .help(tab.displayTitle)
    }
}
