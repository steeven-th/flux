import SwiftUI

/// Which DevTools tools the developer bar shows, and in what order.
struct DeveloperSettings: View {
    @Bindable var state: BrowserState

    @State private var dragged: DevTool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the tools of the developer bar, shown on sites in developer mode. Drag them to change their order.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 2) {
                ForEach(state.devToolsInBar) { tool in
                    Image(systemName: tool.symbol)
                        .frame(width: 26, height: 26)
                }
                if state.devToolsInBar.isEmpty {
                    Text("No tools").foregroundStyle(.secondary).frame(height: 26)
                }
            }
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.06)))
            .help("The developer bar")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(state.devToolsOrder) { tool in
                        ToolRow(state: state, tool: tool)
                            .opacity(dragged == tool ? 0.4 : 1)
                            .onDrag {
                                dragged = tool
                                return NSItemProvider(object: tool.rawValue as NSString)
                            }
                            .onDrop(of: [.text], delegate: ToolDropDelegate(target: tool, state: state, dragged: $dragged))
                        Divider()
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.12)))
            Button("Restore Defaults") {
                state.devToolsOrder = DevTool.allCases
                state.shownDevTools = Set(DevTool.standard)
            }
            Divider()
            Picker("Background in responsive mode:", selection: $state.responsiveBackdrop) {
                ForEach(ResponsiveBackdrop.allCases, id: \.self) { backdrop in
                    Text(backdrop.name).tag(backdrop)
                }
            }
            .fixedSize()
        }
        .padding(20)
        .frame(width: 560, height: 570)
    }
}

private struct ToolRow: View {
    let state: BrowserState
    let tool: DevTool

    var body: some View {
        HStack(spacing: 10) {
            Toggle(tool.name, isOn: Binding(
                get: { state.shownDevTools.contains(tool) },
                set: { isOn in
                    var shown = state.shownDevTools
                    if isOn { shown.insert(tool) } else { shown.remove(tool) }
                    state.shownDevTools = shown
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            Image(systemName: tool.symbol).frame(width: 20)
            Text(tool.name)
            Spacer()
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// Moves the dragged tool as it passes over the others, so the list shows where it will land.
private struct ToolDropDelegate: DropDelegate {
    let target: DevTool
    let state: BrowserState
    @Binding var dragged: DevTool?

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        var order = state.devToolsOrder
        guard let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: target) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
            state.devToolsOrder = order
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}
