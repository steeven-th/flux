import SwiftUI

/// Where the window put the page in responsive mode, for the toolbar, rulers and handles drawn
/// around it.
@MainActor
@Observable
final class ResponsiveLayout {
    /// From the top left corner of the page area.
    var pageFrame = CGRect.zero
    /// Page points per CSS pixel.
    var scale = 1.0
}

/// Everything around a page in responsive mode, like DevTools' device toolbar. The page itself is
/// a window of its own, laid over this view.
struct ResponsiveView: View {
    let state: BrowserState
    let layout: ResponsiveLayout

    static let toolbarHeight: CGFloat = 34
    static let rulerSize: CGFloat = 16
    static let handleSize: CGFloat = 12

    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        if let tab = state.selectedTab, let emulation = tab.emulation {
            let options = state.responsiveOptions
            let page = layout.pageFrame
            ZStack(alignment: .topLeading) {
                backdrop
                if options.contains(.rulers) {
                    Ruler(axis: .horizontal, length: emulation.width, scale: layout.scale)
                        .frame(width: page.width, height: Self.rulerSize)
                        .offset(x: page.minX, y: page.minY - Self.rulerSize)
                    Ruler(axis: .vertical, length: emulation.height, scale: layout.scale)
                        .frame(width: Self.rulerSize, height: page.height)
                        .offset(x: page.minX - Self.rulerSize, y: page.minY)
                }
                // Only Responsive's size is free, a device keeps its own.
                if emulation.device == nil {
                    ResizeHandle(edges: .trailing, tab: tab, scale: layout.scale)
                        .frame(width: Self.handleSize, height: page.height)
                        .offset(x: page.maxX, y: page.minY)
                    ResizeHandle(edges: .bottom, tab: tab, scale: layout.scale)
                        .frame(width: page.width, height: Self.handleSize)
                        .offset(x: page.minX, y: page.maxY)
                    ResizeHandle(edges: [.trailing, .bottom], tab: tab, scale: layout.scale)
                        .frame(width: Self.handleSize, height: Self.handleSize)
                        .offset(x: page.maxX, y: page.maxY)
                }
                DeviceToolbar(state: state, tab: tab, emulation: emulation, options: options, scale: layout.scale)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.toolbarHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.colorScheme, scheme)
        }
    }

    private var scheme: ColorScheme {
        switch state.responsiveBackdrop {
        case .system: systemScheme
        case .dark: .dark
        case .light: .light
        }
    }

    /// Chrome's light background is a pale blue gray rather than white, which would merge with
    /// most pages.
    private var backdrop: Color {
        scheme == .dark ? Color(white: 0.16) : Color(red: 0.89, green: 0.92, blue: 0.97)
    }
}

private struct DeviceToolbar: View {
    let state: BrowserState
    let tab: Tab
    let emulation: Emulation
    let options: Set<ResponsiveOption>
    let scale: Double

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Toggle("Responsive", isOn: Binding(get: { emulation.device == nil }, set: { _ in tab.emulate(nil) }))
                ForEach(EmulatedDevice.Category.allCases, id: \.self) { category in
                    Section(category.name) {
                        ForEach(EmulatedDevice.all.filter { $0.category == category }) { device in
                            Toggle(isOn: Binding(get: { emulation.device?.id == device.id }, set: { _ in tab.emulate(device) })) {
                                Text(verbatim: device.name)
                            }
                        }
                    }
                }
            } label: {
                Text(verbatim: emulation.device?.name ?? String(localized: "Responsive"))
            }
            .fixedSize()

            HStack(spacing: 4) {
                SizeField(value: emulation.width) { tab.resize(width: $0, height: emulation.height) }
                Text(verbatim: "×").foregroundStyle(.secondary)
                SizeField(value: emulation.height) { tab.resize(width: emulation.width, height: $0) }
            }

            Menu {
                ForEach(EmulationZoom.allCases, id: \.self) { zoom in
                    Toggle(zoom.name, isOn: Binding(get: { emulation.zoom == zoom }, set: { _ in tab.zoom(zoom) }))
                }
            } label: {
                Text(verbatim: emulation.zoom == .fit
                    ? "\(EmulationZoom.fit.name) (\(scale.formatted(.percent.precision(.fractionLength(0)))))"
                    : emulation.zoom.name)
            }
            .fixedSize()

            if options.contains(.pixelRatio) {
                Menu {
                    ForEach([1, 1.5, 2, 2.625, 3, 4], id: \.self) { ratio in
                        Toggle(isOn: Binding(get: { emulation.scale == ratio }, set: { _ in tab.setPixelRatio(ratio) })) {
                            Text(verbatim: ratio.formatted())
                        }
                    }
                } label: {
                    Text("DPR: \(emulation.scale.formatted())")
                }
                .fixedSize()
            }

            if options.contains(.deviceType) {
                Menu {
                    ForEach(EmulatedDeviceType.allCases, id: \.self) { type in
                        Toggle(type.name, isOn: Binding(get: { emulation.type == type }, set: { _ in tab.setDeviceType(type) }))
                    }
                } label: {
                    Text(verbatim: emulation.type.name)
                }
                .fixedSize()
            }

            Menu {
                ForEach(NetworkThrottling.allCases, id: \.self) { throttling in
                    Toggle(throttling.name, isOn: Binding(get: { emulation.throttling == throttling }, set: { _ in tab.throttle(throttling) }))
                }
            } label: {
                Text(verbatim: emulation.throttling.name)
            }
            .fixedSize()

            // A borderless button grays its image, which looks disabled next to the menus.
            Button { tab.rotate() } label: {
                Image(systemName: "rectangle.portrait.rotate")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rotate")

            Menu {
                OptionToggle(state: state, option: .rulers, title: "Show Rulers")
                OptionToggle(state: state, option: .pixelRatio, title: "Show Device Pixel Ratio")
                OptionToggle(state: state, option: .deviceType, title: "Show Device Type")
                Divider()
                Button("Capture Screenshot") { PageCapture.captureVisibleArea(of: tab, state: state) }
                Button("Capture Full Size Screenshot") { PageCapture.captureWholePage(of: tab, state: state) }
                Divider()
                Button("Reset to Defaults") { tab.resetEmulation() }
                Button("Close Responsive Mode") { tab.toggleResponsive() }
            } label: {
                Image(systemName: "ellipsis")
            }
            .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.borderless)
        .symbolRenderingMode(.monochrome)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.primary.opacity(0.05))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct OptionToggle: View {
    let state: BrowserState
    let option: ResponsiveOption
    let title: LocalizedStringKey

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { state.responsiveOptions.contains(option) },
            set: { isOn in
                var options = state.responsiveOptions
                if isOn { options.insert(option) } else { options.remove(option) }
                state.responsiveOptions = options
            }
        ))
    }
}

/// A size in CSS pixels, applied when the user presses Return or leaves the field.
private struct SizeField: View {
    let value: Int
    let onCommit: (Int) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(text: $text) { EmptyView() }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 56)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { if !isFocused { commit() } }
            .onAppear { text = String(value) }
            .onChange(of: value) { text = String(value) }
    }

    private func commit() {
        if let number = Int(text.trimmingCharacters(in: .whitespaces)), number != value {
            onCommit(number)
        } else {
            text = String(value)
        }
    }
}

/// Drags the page's free size. The page is centered, so its width grows on both sides at once.
private struct ResizeHandle: View {
    let edges: Edge.Set
    let tab: Tab
    let scale: Double

    @State private var start: (width: Int, height: Int)?

    var body: some View {
        ZStack {
            Rectangle().fill(.primary.opacity(0.08))
            Capsule()
                .fill(.primary.opacity(0.35))
                .frame(width: edges == .trailing ? 3 : 18, height: edges == .bottom ? 3 : 18)
                .opacity(edges == [.trailing, .bottom] ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onHover { isInside in
            if isInside { cursor.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { drag in
                    guard let emulation = tab.emulation else { return }
                    let start = start ?? (emulation.width, emulation.height)
                    self.start = start
                    let width = edges.contains(.trailing) ? start.width + Int(drag.translation.width * 2 / scale) : start.width
                    let height = edges.contains(.bottom) ? start.height + Int(drag.translation.height / scale) : start.height
                    tab.resize(width: width, height: height)
                }
                .onEnded { _ in start = nil }
        )
    }

    private var cursor: NSCursor {
        switch edges {
        case .trailing: .resizeLeftRight
        case .bottom: .resizeUpDown
        default: .crosshair
        }
    }
}

/// Graduated in CSS pixels, like DevTools' rulers.
private struct Ruler: View {
    let axis: Axis
    let length: Int
    let scale: Double

    var body: some View {
        Canvas { context, size in
            // Ticks every 10 pixels, longer every 50, labeled every 100, fewer when they get too close.
            let step = scale < 0.4 ? 50 : 10
            for value in stride(from: 0, through: length, by: step) {
                let position = Double(value) * scale
                let tick: Double = value % 100 == 0 ? size.minor(axis) : value % 50 == 0 ? size.minor(axis) * 0.5 : size.minor(axis) * 0.25
                var path = Path()
                if axis == .horizontal {
                    path.move(to: CGPoint(x: position, y: size.height))
                    path.addLine(to: CGPoint(x: position, y: size.height - tick))
                } else {
                    path.move(to: CGPoint(x: size.width, y: position))
                    path.addLine(to: CGPoint(x: size.width - tick, y: position))
                }
                context.stroke(path, with: .color(.secondary), lineWidth: 0.5)
                let labelEvery = scale < 0.4 ? 200 : 100
                if value % labelEvery == 0, value > 0 {
                    let label = context.resolve(Text(verbatim: "\(value)").font(.system(size: 8)).foregroundStyle(.secondary))
                    if axis == .horizontal {
                        context.draw(label, at: CGPoint(x: position + 2, y: 1), anchor: .topLeading)
                    } else {
                        var rotated = context
                        rotated.translateBy(x: 1, y: position - 2)
                        rotated.rotate(by: .degrees(-90))
                        rotated.draw(label, at: .zero, anchor: .topLeading)
                    }
                }
            }
        }
        .background(.primary.opacity(0.06))
    }
}

private extension CGSize {
    func minor(_ axis: Axis) -> Double {
        axis == .horizontal ? height : width
    }
}
