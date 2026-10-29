import SwiftUI

struct GeneralSettings: View {
    let state: BrowserState
    let showProfiles: () -> Void

    @State private var warnsBeforeQuitting = false
    @State private var confirmsTabRemoval = true

    var body: some View {
        Form {
            Section {
                Toggle("Warn before quitting", isOn: $warnsBeforeQuitting)
                Toggle("Ask before closing a pinned tab or a favorite", isOn: $confirmsTabRemoval)
            }
            Section {
                LabeledContent("Each profile has its own search engine, passwords and browsing data.") {
                    Button("Profile Settings…", action: showProfiles)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            warnsBeforeQuitting = state.warnsBeforeQuitting
            confirmsTabRemoval = state.confirmsTabRemoval
        }
        .onChange(of: warnsBeforeQuitting) { state.warnsBeforeQuitting = warnsBeforeQuitting }
        .onChange(of: confirmsTabRemoval) { state.confirmsTabRemoval = confirmsTabRemoval }
    }
}
