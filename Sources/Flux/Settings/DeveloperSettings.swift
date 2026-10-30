import SwiftUI

/// The developer bar's tools, and the devices of the responsive mode.
struct DeveloperSettings: View {
    enum Section: Hashable {
        case tools, devices
    }

    @MainActor
    @Observable
    final class Model {
        var section = Section.tools
    }

    @Bindable var state: BrowserState
    @Bindable var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(selection: $model.section) {
                Text("Tools").tag(Section.tools)
                Text("Devices").tag(Section.devices)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity)
            switch model.section {
            case .tools: ToolSettings(state: state)
            case .devices: DeviceSettings(state: state)
            }
        }
        .padding(20)
        .frame(width: 560, height: 600)
    }
}

/// Which DevTools tools the developer bar shows, and in what order.
private struct ToolSettings: View {
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
        }
    }
}

/// The devices the responsive mode lists: built-in ones to check, and the user's own.
private struct DeviceSettings: View {
    @Bindable var state: BrowserState

    @State private var edited: EmulatedDevice?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the devices listed in responsive mode, or add your own.")
                .foregroundStyle(.secondary)
            List {
                ForEach(EmulatedDevice.Category.allCases.filter { $0 != .custom }, id: \.self) { category in
                    Section(category.name) {
                        ForEach(EmulatedDevice.all.filter { $0.category == category }) { device in
                            Toggle(isOn: Binding(
                                get: { !state.hiddenDevices.contains(device.id) },
                                set: { isOn in
                                    var hidden = state.hiddenDevices
                                    if isOn { hidden.remove(device.id) } else { hidden.insert(device.id) }
                                    state.hiddenDevices = hidden
                                }
                            )) {
                                DeviceLabel(device: device)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                Section(EmulatedDevice.Category.custom.name) {
                    ForEach(state.customDevices) { device in
                        HStack {
                            DeviceLabel(device: device)
                            Spacer()
                            Button("Edit…") { edited = device }
                            Button {
                                state.customDevices.removeAll { $0.id == device.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Remove")
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("Add a Device…") { edited = .custom() }
                        .buttonStyle(.borderless)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            Divider()
            Picker("Background in responsive mode:", selection: $state.responsiveBackdrop) {
                ForEach(ResponsiveBackdrop.allCases, id: \.self) { backdrop in
                    Text(backdrop.name).tag(backdrop)
                }
            }
            .fixedSize()
        }
        .sheet(item: $edited) { device in
            DeviceForm(device: device) { saved in
                var devices = state.customDevices
                if let index = devices.firstIndex(where: { $0.id == saved.id }) {
                    devices[index] = saved
                } else {
                    devices.append(saved)
                }
                state.customDevices = devices
            }
        }
    }
}

private struct DeviceLabel: View {
    let device: EmulatedDevice

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: device.name)
            Text(verbatim: "\(device.width) × \(device.height) · \(device.scale.formatted())x")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct DeviceForm: View {
    @State var device: EmulatedDevice
    let onSave: (EmulatedDevice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            Form {
                TextField("Name:", text: $device.name)
                TextField("Width:", value: $device.width, format: .number.grouping(.never))
                TextField("Height:", value: $device.height, format: .number.grouping(.never))
                TextField("Device pixel ratio:", value: $device.scale, format: .number)
                Toggle("Mobile, with touch", isOn: $device.isMobile)
                TextField("User agent:", text: Binding(
                    get: { device.userAgent ?? "" },
                    set: { device.userAgent = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Default"), axis: .vertical)
                .lineLimit(2...4)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    device.width = min(max(device.width, 50), 4000)
                    device.height = min(max(device.height, 50), 4000)
                    device.scale = min(max(device.scale, 0.5), 5)
                    onSave(device)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(device.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
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
