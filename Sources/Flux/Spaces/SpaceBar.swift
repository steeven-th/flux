import SwiftUI

/// The row of spaces at the bottom of the sidebar.
struct SpaceBar: View {
    let state: BrowserState

    @State private var editedSpaceID: UUID?
    @State private var isCreating = false
    @State private var spaceToDelete: Space?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(state.spaces.enumerated()), id: \.element.id) { index, space in
                SpaceIcon(space: space, isSelected: space.id == state.selectedSpaceID)
                    .onTapGesture { state.selectedSpaceID = space.id }
                    .help(index < 9 ? "\(space.name) (⌃\(index + 1))" : space.name)
                    .contextMenu {
                        Button("Edit Space…") { editedSpaceID = space.id }
                        Button("Delete Space…", role: .destructive) { spaceToDelete = space }
                            .disabled(state.spaces.count == 1)
                    }
                    .popover(isPresented: editingBinding(for: space.id), arrowEdge: .top) {
                        SpaceEditor(title: "Edit Space", space: space) { name, icon, color in
                            state.updateSpace(space.id, name: name, icon: icon, color: color)
                            editedSpaceID = nil
                        } onCancel: {
                            editedSpaceID = nil
                        }
                    }
            }
            Spacer(minLength: 0)
            Button {
                isCreating = true
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("New Space")
            .popover(isPresented: $isCreating, arrowEdge: .top) {
                SpaceEditor(title: "New Space", space: nil) { name, icon, color in
                    state.createSpace(name: name, icon: icon, color: color)
                    isCreating = false
                } onCancel: {
                    isCreating = false
                }
            }
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

    private var deleteTitle: String {
        String(localized: "Delete “\(spaceToDelete?.name ?? "")”?")
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { spaceToDelete != nil }, set: { if !$0 { spaceToDelete = nil } })
    }

    private func editingBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { editedSpaceID == id }, set: { if !$0 { editedSpaceID = nil } })
    }
}

private struct SpaceIcon: View {
    let space: Space
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(space.color.opacity(isSelected ? 0.9 : 0.35))
            if let icon = space.icon, !icon.isEmpty {
                Text(icon).font(.system(size: 12))
            } else {
                Text(space.name.prefix(1).uppercased())
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
