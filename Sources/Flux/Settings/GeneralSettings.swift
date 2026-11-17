import SwiftUI

struct GeneralSettings: View {
    let state: BrowserState
    let showProfiles: () -> Void

    @State private var warnsBeforeQuitting = false
    @State private var confirmsTabRemoval = true
    @State private var tabSleepDelay = TabSleepDelay.standard
    @State private var spaceBarLayout = BrowserState.SpaceBarLayout.dots
    @State private var blocksContent = true
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
                Toggle("Block ads and trackers", isOn: $blocksContent)
            } footer: {
                Text("Uses the EasyList and EasyPrivacy lists, updated every few days. Turn it off for one site from the page menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("When spaces don't fit", selection: $spaceBarLayout) {
                    ForEach(BrowserState.SpaceBarLayout.allCases) { layout in
                        Text(layout.name).tag(layout)
                    }
                }
            } footer: {
                Text("How the bar at the bottom of the sidebar shows spaces when their icons don't fit in its width. Past what dots can show, arrows scroll them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Put inactive tabs to sleep after", selection: $tabSleepDelay) {
                    ForEach(TabSleepDelay.allCases) { delay in
                        Text(delay.name).tag(delay)
                    }
                }
            } footer: {
                Text("Their page is unloaded to free memory, and loads again when you open them, where you left it. Tabs playing sound or a video stay awake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TranslationSettings(state: state)
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
            tabSleepDelay = state.tabSleepDelay
            spaceBarLayout = state.spaceBarLayout
            blocksContent = state.blocksContent
        }
        .onChange(of: tabSleepDelay) { state.tabSleepDelay = tabSleepDelay }
        .onChange(of: spaceBarLayout) { state.spaceBarLayout = spaceBarLayout }
        .onChange(of: blocksContent) { state.blocksContent = blocksContent }
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
