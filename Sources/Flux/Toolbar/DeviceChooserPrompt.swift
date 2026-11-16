import SwiftUI

/// A page asking for a Bluetooth, USB, HID or serial device, under the address in place of
/// Chrome's bubble. The list fills in as devices are found.
struct DeviceChooserPrompt: View {
    let chooser: FLXDeviceChooser
    let onChoose: (Int?) -> Void

    @State private var selection: Int?
    /// Bumped when the chooser changes, which the view can't observe otherwise.
    @State private var revision = 0

    var body: some View {
        let _ = revision
        VStack(alignment: .leading, spacing: 12) {
            Text(chooser.title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            if chooser.isBluetoothRefused {
                SystemNotice(text: "macOS doesn't let Flux use Bluetooth.", action: chooser.openSystemSettings)
            } else if chooser.isBluetoothOff {
                SystemNotice(text: "Bluetooth is off.", action: chooser.openSystemSettings)
            } else {
                List(selection: $selection) {
                    ForEach(Array(chooser.options.enumerated()), id: \.offset) { index, option in
                        Text(option).tag(index)
                    }
                }
                .listStyle(.bordered)
                .frame(height: 150)
                .overlay {
                    if chooser.options.isEmpty {
                        if chooser.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(chooser.emptyText)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    }
                }
            }

            HStack {
                if chooser.canRescan {
                    Button("Scan Again", action: chooser.rescan)
                        .disabled(chooser.isScanning)
                }
                Spacer()
                Button("Cancel") { onChoose(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(chooser.selectTitle) { onChoose(selection) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            chooser.onChange = {
                revision += 1
                if let index = selection, index >= chooser.options.count { selection = nil }
            }
        }
    }
}

private struct SystemNotice: View {
    let text: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Button("Open System Settings", action: action)
        }
        .font(.callout)
    }
}
