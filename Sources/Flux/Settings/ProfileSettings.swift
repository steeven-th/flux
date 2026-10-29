import SwiftUI

/// Settings of each Chromium profile. A profile has no name of its own and is shown under the names
/// of the spaces using it.
struct ProfileSettings: View {
    let state: BrowserState

    @State private var selection: URL?

    var body: some View {
        let profiles = state.profilesInUse
        VStack(alignment: .leading, spacing: 12) {
            Text("Profiles keep history, passwords, cookies and extensions apart. Each space uses a profile, and spaces can share one.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                List(profiles, selection: $selection) { profile in
                    HStack {
                        Text(profile.name).lineLimit(1)
                        Spacer()
                        Text("\(profile.spaces.count) Spaces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(profile.folder)
                }
                .listStyle(.bordered)
                .frame(width: 200)
                if let profile = profiles.first(where: { $0.folder == selection }) {
                    ProfileDetail(state: state, profile: profile)
                        .id(profile.folder)
                }
            }
        }
        .padding(20)
        .frame(width: 680, height: 500)
        .onAppear {
            if selection == nil { selection = state.selectedSpace.profileFolder.standardizedFileURL }
        }
    }
}

private struct ProfileDetail: View {
    let state: BrowserState
    let profile: BrowserState.Profile

    private static let customID = "custom"
    private static let placeholder = "%s"

    @State private var engineID = SearchEngine.google.id
    @State private var archiveDelay = ArchiveDelay.standard
    @State private var asksWhereToSave = false
    @State private var customTemplate = ""

    var body: some View {
        Form {
            Section {
                Picker("Search engine", selection: $engineID) {
                    ForEach(SearchEngine.all) { engine in
                        Text(engine.name).tag(engine.id)
                    }
                    Divider()
                    Text("Custom…").tag(Self.customID)
                }
                if engineID == Self.customID {
                    TextField("Search URL", text: $customTemplate, prompt: Text(verbatim: "https://example.com/search?q=%s"))
                    (isValid(customTemplate)
                        ? Text("Searches go to this address, with the words in place of \(Self.placeholder).")
                        : Text("Enter a web address with \(Self.placeholder) where the searched words go."))
                        .font(.caption)
                        .foregroundStyle(isValid(customTemplate) ? Color.secondary : Color.red)
                }
            }
            if let passwords = state.passwordManager(forProfile: profile.folder),
               let extensions = state.extensionList(forProfile: profile.folder) {
                PasswordsSection(passwords: passwords, extensions: extensions, show: show)
            }
            Section {
                Picker("Archive tabs after", selection: $archiveDelay) {
                    ForEach(ArchiveDelay.allCases) { delay in
                        Text(delay.name).tag(delay)
                    }
                }
                Picker("Downloads", selection: $asksWhereToSave) {
                    Text("Save to the Downloads folder").tag(false)
                    Text("Ask where to save each file").tag(true)
                }
            } footer: {
                Text("Tabs of Today you haven't looked at for this long go to the archive, at the bottom of the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Your Data and Settings") {
                ChromePageRow(title: "Privacy and Security", symbol: "lock.fill", color: .blue) {
                    show("chrome://settings/privacy")
                }
                ChromePageRow(title: "Passwords", symbol: "key.fill", color: .green) {
                    show("chrome://password-manager")
                }
                ChromePageRow(title: "Payment Methods", symbol: "creditcard.fill", color: .yellow) {
                    show("chrome://settings/payments")
                }
                ChromePageRow(title: "Notifications", symbol: "bell.fill", color: .orange) {
                    show("chrome://settings/content/notifications")
                }
                ChromePageRow(title: "Clear Browsing Data", symbol: "trash.fill", color: .red) {
                    show("chrome://settings/clearBrowserData")
                }
                ChromePageRow(title: "All Chromium Settings", symbol: "gearshape.fill", color: .gray) {
                    show("chrome://settings")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            archiveDelay = state.archiveDelay(forProfile: profile.folder)
            asksWhereToSave = state.asksWhereToSaveDownloads(forProfile: profile.folder)
            let engine = state.searchEngine(forProfile: profile.folder)
            if SearchEngine.all.contains(engine) {
                engineID = engine.id
            } else {
                engineID = Self.customID
                customTemplate = engine.template
            }
        }
        .onChange(of: engineID) { save() }
        .onChange(of: archiveDelay) { state.setArchiveDelay(archiveDelay, forProfile: profile.folder) }
        .onChange(of: asksWhereToSave) { state.setAsksWhereToSaveDownloads(asksWhereToSave, forProfile: profile.folder) }
        .onChange(of: customTemplate) { save() }
    }

    private func isValid(_ template: String) -> Bool {
        let scheme = URL(string: template.replacingOccurrences(of: "%s", with: "x"))?.scheme
        return template.contains("%s") && (scheme == "https" || scheme == "http")
    }

    private func save() {
        if engineID == Self.customID {
            guard isValid(customTemplate) else { return }
            state.setSearchEngine(SearchEngine(setting: customTemplate), forProfile: profile.folder)
        } else {
            state.setSearchEngine(SearchEngine(setting: engineID), forProfile: profile.folder)
        }
    }

    /// Chromium's pages open as a tab of a space using the profile, in Flux's window.
    private func show(_ url: String) {
        state.showChromePage(url, forProfile: profile.folder)
        NSApp.windows.first { $0 is MainWindow }?.makeKeyAndOrderFront(nil)
    }
}

private struct PasswordsSection: View {
    let passwords: ChromiumPasswordManager
    let extensions: ExtensionList
    let show: (String) -> Void

    var body: some View {
        Section("Passwords") {
            Toggle(isOn: Binding(get: { passwords.isEnabled }, set: { passwords.setEnabled($0) })) {
                Text("Chromium Password Manager")
                Text("Saves passwords on this Mac, in this profile. No account needed.")
            }
            if passwords.isEnabled, let other = enabledManagers.first {
                LabeledContent("\(other.name) also offers to save passwords, so you may be asked twice.") {
                    Button("Turn Off Chromium's") { passwords.setEnabled(false) }
                }
                .font(.callout)
            }
            ForEach(PasswordManagerExtension.all) { manager in
                PasswordManagerRow(
                    manager: manager,
                    installed: extensions.extensions.first { $0.id == manager.id },
                    isInstalled: extensions.installedIDs.contains(manager.id),
                    show: show
                )
            }
        }
    }

    private var enabledManagers: [PasswordManagerExtension] {
        PasswordManagerExtension.all.filter { manager in extensions.extensions.contains { $0.id == manager.id } }
    }
}

/// A password manager extension: greyed out with a link to the Chrome Web Store until it is
/// installed. Chromium has no API to turn an extension on or off from outside its own extension
/// page, so installed ones link there.
private struct PasswordManagerRow: View {
    let manager: PasswordManagerExtension
    /// Set while the extension is enabled.
    let installed: InstalledExtension?
    let isInstalled: Bool
    let show: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = installed?.icon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "key.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            Text(manager.name)
                .foregroundStyle(isInstalled ? .primary : .secondary)
            Spacer()
            if isInstalled {
                (installed == nil ? Text("Off") : Text("On"))
                    .font(.callout)
                    .foregroundStyle(installed == nil ? Color.secondary : Color.green)
                Button("Manage") { show(manager.manageURL) }
            } else {
                Button("Get") { show(manager.storeURL) }
            }
        }
    }
}

private struct ChromePageRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color))
                Text(title)
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
