import SwiftUI

/// The spaces at the bottom of the sidebar. When their icons don't fit, they show as dots, scroll
/// between arrows, or wrap on rows of their own, as chosen in the settings.
struct SpaceBar: View {
    let state: BrowserState
    let recentFiles: RecentFilesPresenter

    @State private var editedSpaceID: UUID?
    @State private var isCreating = false
    @State private var spaceToDelete: Space?
    @State private var rowWidth: CGFloat = 0
    @State private var barWidth: CGFloat = 0
    @State private var firstShownID: UUID?

    private static let sideWidth: CGFloat = 48
    private static let iconSize: CGFloat = 22
    private static let dotSize: CGFloat = 7
    private static let dotSpacing: CGFloat = 5
    private static let spacing: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !state.isPrivate, state.spaceBarLayout == .rows {
                FlowLayout(spacing: Self.spacing) {
                    ForEach(Array(state.spaces.enumerated()), id: \.element.id) { index, space in
                        spaceItem(space, index: index, isDot: false)
                    }
                }
                .padding(.horizontal, 4)
            }
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    LibraryButton(state: state, recentFiles: recentFiles)
                    ArchiveButton(state: state)
                }
                .frame(width: Self.sideWidth, alignment: .leading)
                // Private windows have one space, which can't be changed.
                if state.isPrivate {
                    Label("Private Browsing", systemImage: "eyeglasses")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    if state.spaceBarLayout == .rows {
                        Spacer()
                    } else {
                        spaceRow
                    }
                    // As wide as the buttons on the left, so the spaces sit in the sidebar's middle,
                    // unless they need the room.
                    newSpaceButton
                        .frame(width: isCrowded ? Self.iconSize : Self.sideWidth, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        }
        .alert(deleteTitle, isPresented: deletingBinding, presenting: spaceToDelete) { space in
            Button("Delete", role: .destructive) { state.deleteSpace(space.id) }
            Button("Cancel", role: .cancel) {}
        } message: { space in
            state.ownsProfile(space.id)
                ? Text("Its tabs, sign-ins, saved passwords, history and extensions will be deleted. This can't be undone.")
                : Text("Its tabs will be deleted. Sign-ins and extensions stay with the other spaces using the same profile.")
        }
    }

    private var iconsFit: Bool {
        let count = CGFloat(state.spaces.count)
        return count * Self.iconSize + (count - 1) * Self.spacing <= rowWidth
    }

    private var dotsFit: Bool {
        let others = CGFloat(state.spaces.count - 1)
        return Self.iconSize + others * (Self.dotSize + Self.dotSpacing) <= rowWidth
    }

    /// Whether the icons need the room the + button leaves for symmetry. Worked out from the whole
    /// bar's width, which the icons don't change.
    private var isCrowded: Bool {
        let count = CGFloat(state.spaces.count)
        let symmetricRow = barWidth - 2 * Self.sideWidth - 2 * 6
        return count * Self.iconSize + (count - 1) * Self.spacing > symmetricRow
    }

    /// Measured on an empty view that takes the room left, so the icons never widen the sidebar.
    private var spaceRow: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.iconSize)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .overlay { spaceRowContent }
            .clipped()
    }

    private var spaceRowContent: some View {
        Group {
            if iconsFit {
                HStack(spacing: Self.spacing) {
                    ForEach(Array(state.spaces.enumerated()), id: \.element.id) { index, space in
                        spaceItem(space, index: index, isDot: false)
                    }
                }
                .frame(maxWidth: .infinity)
            } else if state.spaceBarLayout == .dots, dotsFit {
                HStack(spacing: Self.dotSpacing) {
                    ForEach(Array(state.spaces.enumerated()), id: \.element.id) { index, space in
                        spaceItem(space, index: index, isDot: space.id != state.selectedSpaceID)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                scrollingRow
            }
        }
    }

    /// The icons that fit, between arrows that bring the others in.
    private var scrollingRow: some View {
        let visible = max(Int((rowWidth - 2 * 16 + Self.spacing) / (Self.iconSize + Self.spacing)), 1)
        let ids = state.spaces.map(\.id)
        let first = firstShownID.flatMap { ids.firstIndex(of: $0) } ?? 0
        return HStack(spacing: 0) {
            arrow("chevron.left", isEnabled: first > 0) {
                firstShownID = ids[max(first - visible, 0)]
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.spacing) {
                    ForEach(Array(state.spaces.enumerated()), id: \.element.id) { index, space in
                        spaceItem(space, index: index, isDot: false)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $firstShownID, anchor: .leading)
            // Whole icons only.
            .frame(width: CGFloat(visible) * (Self.iconSize + Self.spacing) - Self.spacing)
            arrow("chevron.right", isEnabled: first + visible < ids.count) {
                firstShownID = ids[min(first + visible, max(ids.count - visible, 0))]
            }
        }
        .onChange(of: state.selectedSpaceID) {
            // The selected space comes into view, as when switching with ⌃1 to ⌃9.
            guard let index = ids.firstIndex(of: state.selectedSpaceID), index < first || index >= first + visible else { return }
            firstShownID = ids[max(min(index, ids.count - visible), 0)]
        }
        .animation(.easeOut(duration: 0.2), value: firstShownID)
    }

    private func arrow(_ symbol: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
    }

    private func spaceItem(_ space: Space, index: Int, isDot: Bool) -> some View {
        Group {
            if isDot {
                Circle()
                    .fill(space.color.opacity(0.6))
                    .frame(width: Self.dotSize, height: Self.dotSize)
                    .frame(width: Self.dotSize, height: Self.iconSize)
                    .contentShape(Rectangle())
            } else {
                SpaceIcon(space: space, isSelected: space.id == state.selectedSpaceID)
            }
        }
        .id(space.id)
        .onTapGesture { state.selectedSpaceID = space.id }
        .help(index < 9 ? "\(space.name) (⌃\(index + 1))" : space.name)
        .contextMenu {
            Button("Customize Space…") { editedSpaceID = space.id }
            Button("Delete Space…", role: .destructive) { spaceToDelete = space }
                .disabled(state.spaces.count == 1)
        }
        // Beside the sidebar, which shows the new look as it's chosen.
        .popover(isPresented: editingBinding(for: space.id), arrowEdge: .trailing) {
            SpaceEditor(
                title: "Customize Space", space: space,
                sharesProfileWith: state.spaces(sharingProfileOf: space.id).filter { $0.id != space.id }.map(\.name)
            ) { name, icon, theme, _ in
                state.updateSpace(space.id, name: name, icon: icon, theme: theme)
                editedSpaceID = nil
            } onCancel: {
                editedSpaceID = nil
            } onPreview: { theme in
                state.previewTheme(theme, of: space.id)
            }
        }
    }

    private var newSpaceButton: some View {
        Button {
            isCreating = true
        } label: {
            Image(systemName: "plus")
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("New Space")
        .popover(isPresented: Binding(get: { isCreating }, set: {
            if !$0 { SpaceEditor.closeColorPanel() }
            isCreating = $0
        }), arrowEdge: .top) {
            SpaceEditor(title: "New Space", space: nil, profiles: state.profilesInUse) { name, icon, theme, other in
                state.createSpace(name: name, icon: icon, color: theme.color, theme: theme, sharingProfileOf: other)
                isCreating = false
            } onCancel: {
                isCreating = false
            }
        }
    }

    private var deleteTitle: String {
        String(localized: "Delete “\(spaceToDelete?.name ?? "")”?")
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { spaceToDelete != nil }, set: { if !$0 { spaceToDelete = nil } })
    }

    private func editingBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { editedSpaceID == id }, set: {
            guard !$0 else { return }
            SpaceEditor.closeColorPanel()
            editedSpaceID = nil
        })
    }
}

struct SpaceIcon: View {
    let name: String
    let icon: String?
    var symbol: String?
    let color: Color
    let isSelected: Bool

    init(name: String, icon: String?, symbol: String? = nil, color: Color, isSelected: Bool) {
        self.name = name
        self.icon = icon
        self.symbol = symbol
        self.color = color
        self.isSelected = isSelected
    }

    init(space: Space, isSelected: Bool) {
        self.init(name: space.name, icon: space.icon, symbol: space.theme.symbol, color: space.color, isSelected: isSelected)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isSelected ? 0.9 : 0.35))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            } else if let icon, !icon.isEmpty {
                Text(icon).font(.system(size: 12))
            } else {
                Text(name.prefix(1).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .overlay {
            Circle().strokeBorder(.white.opacity(isSelected ? 0.8 : 0), lineWidth: 1.5)
        }
        .contentShape(Circle())
    }
}

struct ArchiveButton: View {
    @Bindable var state: BrowserState

    var body: some View {
        Button {
            state.isArchiveShown.toggle()
        } label: {
            Image(systemName: "archivebox")
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Archive")
        .popover(isPresented: $state.isArchiveShown, arrowEdge: .top) {
            ArchiveView(state: state)
        }
    }
}

/// Lays its views out left to right, starting a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if var row = rows.last, row.width + spacing + size.width <= width {
                row.indices.append(index)
                row.width += spacing + size.width
                row.height = max(row.height, size.height)
                rows[rows.count - 1] = row
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
