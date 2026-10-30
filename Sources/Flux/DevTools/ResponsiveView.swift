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
    let tab: Tab
    let layout: ResponsiveLayout

    static let toolbarHeight: CGFloat = 34
    static let rulerSize: CGFloat = 16
    static let handleSize: CGFloat = 12
    static let mediaQueriesHeight: CGFloat = MediaQueryBars.height + 6

    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        if let emulation = tab.emulation {
            let options = state.responsiveOptions
            let page = layout.pageFrame
            ZStack(alignment: .topLeading) {
                backdrop
                if options.contains(.mediaQueries) {
                    let ruler = options.contains(.rulers) ? Self.rulerSize : 0
                    MediaQueryBars(tab: tab, center: page.midX, scale: layout.scale)
                        .frame(height: MediaQueryBars.height)
                        .offset(y: page.minY - ruler - Self.mediaQueriesHeight)
                }
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
                let devices = state.emulatedDevices
                ForEach(EmulatedDevice.Category.allCases, id: \.self) { category in
                    let inCategory = devices.filter { $0.category == category }
                    if !inCategory.isEmpty {
                        Section(category.name) {
                            ForEach(inCategory) { device in
                                Toggle(isOn: Binding(get: { emulation.device?.id == device.id }, set: { _ in tab.emulate(device) })) {
                                    Text(verbatim: device.name)
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Edit…") { SettingsWindowController.showDevices(state: state) }
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
                OptionToggle(state: state, option: .mediaQueries, title: "Show Media Queries")
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

/// One row per kind of query, like DevTools': up to a width, between two, and from a width. The
/// page grows on both sides of its center, so each bar is centered on it too.
private struct MediaQueryBars: View {
    static let rowHeight: CGFloat = 10
    static let height = rowHeight * 3 + 4

    let tab: Tab
    let center: CGFloat
    let scale: Double

    @State private var hovered: MediaQuery?
    @State private var pointer = CGPoint.zero

    var body: some View {
        GeometryReader { geometry in
            let edge = max(center, geometry.size.width - center)
            VStack(spacing: 2) {
                ForEach(MediaQuery.Kind.allCases, id: \.self) { kind in
                    let queries = tab.mediaQueries.filter { $0.kind == kind }
                    ZStack(alignment: .topLeading) {
                        // Narrower bars over wider ones. A larger minimum width leaves narrower bars.
                        ForEach(kind == .min ? queries.reversed() : queries, id: \.self) { query in
                            bar(for: query, edge: edge)
                        }
                    }
                    .frame(width: geometry.size.width, height: Self.rowHeight, alignment: .topLeading)
                    .clipped()
                    // Bars overlap, so the row finds the one under the pointer itself.
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hovered = query(in: queries, at: location.x)
                            pointer = location
                        case .ended:
                            hovered = nil
                        }
                    }
                    .onTapGesture { location in
                        guard let query = query(in: queries, at: location.x), let emulation = tab.emulation else { return }
                        tab.resize(width: query.width, height: emulation.height)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hovered {
                    Text(verbatim: "@media \(hovered.text)")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.background))
                        .fixedSize()
                        .offset(x: min(pointer.x + 10, geometry.size.width - 260), y: -16)
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear { tab.loadMediaQueries() }
    }

    /// The narrowest of the row's ranges that holds the width at that distance from the center.
    private func query(in queries: [MediaQuery], at x: CGFloat) -> MediaQuery? {
        let width = abs(x - center) * 2 / scale
        return queries
            .filter { $0.contains(width) }
            .min { ($0.max ?? .infinity) - ($0.min ?? 0) < ($1.max ?? .infinity) - ($1.min ?? 0) }
    }

    @ViewBuilder
    private func bar(for query: MediaQuery, edge: CGFloat) -> some View {
        let inner = (query.min ?? 0) * scale / 2
        let outer = query.max.map { $0 * scale / 2 } ?? edge
        let color = color(for: query.kind)
        let isLit = query == hovered || tab.emulation.map { query.contains(Double($0.width)) } == true
        if query.min == nil {
            segment(from: center - outer, to: center + outer, color: color, isLit: isLit)
        } else {
            // Two segments, outside the minimum width on each side, out to the maximum or the edge.
            segment(from: center - outer, to: center - inner, color: color, isLit: isLit)
            segment(from: center + inner, to: center + outer, color: color, isLit: isLit)
        }
    }

    private func segment(from start: CGFloat, to end: CGFloat, color: Color, isLit: Bool) -> some View {
        Rectangle()
            .fill(color.opacity(isLit ? 0.55 : 0.25))
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(color).frame(width: 1) }
            .frame(width: max(end - start, 1), height: Self.rowHeight)
            .offset(x: start)
    }

    private func color(for kind: MediaQuery.Kind) -> Color {
        switch kind {
        case .max: .blue
        case .range: .green
        case .min: .orange
        }
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
