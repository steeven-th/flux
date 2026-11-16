import AVFoundation
import CoreLocation
import SwiftUI

/// What macOS lets Flux use for sites. A site allowed in Flux still gets nothing from what macOS
/// keeps from Flux, and Chromium then asks again on every visit.
enum SystemAccess: CaseIterable {
    case location, camera, microphone

    init?(permissionKey: String) {
        switch permissionKey {
        case "geolocation": self = .location
        case "media_stream_camera": self = .camera
        case "media_stream_mic": self = .microphone
        default: return nil
        }
    }

    static func requested(in permissions: FLXPermission) -> [SystemAccess] {
        allCases.filter { !permissions.intersection($0.permission).isEmpty }
    }

    private var permission: FLXPermission {
        switch self {
        case .location: .geolocation
        case .camera: [.camera, .cameraPanTiltZoom]
        case .microphone: .microphone
        }
    }

    /// Refused in System Settings. Not asked yet isn't refused: macOS asks when a site needs it.
    var isRefused: Bool {
        switch self {
        case .location: [.denied, .restricted].contains(CLLocationManager().authorizationStatus)
        case .camera: [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone: [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .audio))
        }
    }

    var refusedMessage: String {
        switch self {
        case .location: String(localized: "macOS doesn't let Flux use your location.")
        case .camera: String(localized: "macOS doesn't let Flux use your camera.")
        case .microphone: String(localized: "macOS doesn't let Flux use your microphone.")
        }
    }

    func openSystemSettings() {
        let pane = switch self {
        case .location: "Privacy_LocationServices"
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Says what macOS keeps from Flux, with a way to System Settings.
struct SystemAccessNotice: View {
    let accesses: [SystemAccess]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(accesses, id: \.self) { access in
                Label(access.refusedMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text("Allow Flux in System Settings, then reload the page.")
                .foregroundStyle(.secondary)
            Button("Open System Settings") { accesses.first?.openSystemSettings() }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}
