import SwiftUI

/// The colors after the space's own, which make a gradient, and its direction.
struct GradientFields: View {
    @Binding var theme: SpaceTheme

    var body: some View {
        HStack(spacing: 8) {
            Text("Gradient")
            ForEach(theme.colors.indices.dropFirst(), id: \.self) { index in
                ColorPicker("Gradient Color", selection: color(at: index), supportsOpacity: false)
                    .labelsHidden()
            }
            if theme.colors.count < SpaceTheme.maxColors {
                Button {
                    theme.colors.append(theme.nextColor())
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a Color")
            }
            if theme.colors.count > 1 {
                Button {
                    theme.colors.removeLast()
                } label: {
                    Image(systemName: "minus")
                }
                .help("Remove the Last Color")
                Spacer()
                AngleDial(angle: $theme.angle)
                    .help("Direction of the Gradient")
            }
        }
        .buttonStyle(.borderless)
    }

    private func color(at index: Int) -> Binding<Color> {
        Binding(
            get: { Color(hex: theme.colors[index]) },
            set: { if index < theme.colors.count { theme.colors[index] = NSColor($0).hexString } }
        )
    }
}

/// A knob to drag around: its hand points where the gradient goes.
private struct AngleDial: View {
    @Binding var angle: Double
    private let size = 24.0

    var body: some View {
        ZStack {
            Circle().strokeBorder(.secondary, lineWidth: 1.5)
            Capsule()
                .fill(.primary)
                .frame(width: size / 2 - 3, height: 2)
                .offset(x: size / 4 - 1.5)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            let x = drag.location.x - size / 2, y = drag.location.y - size / 2
            guard x != 0 || y != 0 else { return }
            let degrees = atan2(y, x) * 180 / .pi
            // In steps of 15°, which are easier to land on twice.
            angle = ((degrees / 15).rounded() * 15 + 360).truncatingRemainder(dividingBy: 360)
        })
    }
}
