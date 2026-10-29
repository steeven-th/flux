import SwiftUI

struct GeneralSettings: View {
    let state: BrowserState
    let showProfiles: () -> Void

    @State private var warnsBeforeQuitting = false
    @State private var confirmsTabRemoval = true
    @State private var language = AppLanguage.current
    @State private var asksToRelaunch = false
    @State private var isDefaultBrowser = DefaultBrowser.isFlux

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.name).tag(language)
                    }
                }
            }
            Section {
                LabeledContent("Default browser") {
                    if isDefaultBrowser {
                        Text("Flux is your default browser")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Make Flux the Default Browser") {
                            DefaultBrowser.makeFlux { isDefaultBrowser = $0 }
                        }
                    }
                }
            }
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
            isDefaultBrowser = DefaultBrowser.isFlux
            warnsBeforeQuitting = state.warnsBeforeQuitting
            confirmsTabRemoval = state.confirmsTabRemoval
        }
        .onChange(of: warnsBeforeQuitting) { state.warnsBeforeQuitting = warnsBeforeQuitting }
        .onChange(of: confirmsTabRemoval) { state.confirmsTabRemoval = confirmsTabRemoval }
        .onChange(of: language) {
            AppLanguage.choose(language)
            asksToRelaunch = true
        }
        .alert("Relaunch Flux to use the new language?", isPresented: $asksToRelaunch) {
            Button("Relaunch Now") { (NSApp.delegate as? AppDelegate)?.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Your tabs and spaces are kept.")
        }
    }
}
