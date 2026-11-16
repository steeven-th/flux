import SecurityInterface
import SwiftUI

/// What can be done with the page shown: share it, capture it, use the space's extensions, and
/// settings for its site.
struct PageOptions: View {
    @Bindable var state: BrowserState
    let tab: Tab
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if let url = URL(string: tab.url) {
                    ShareLink(item: url) {
                        OptionTile(symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .help("Share")
                }
                Button(action: captureArea) { OptionTile(symbol: "camera") }
                    .buttonStyle(.plain)
                    .help("Capture an Area")
                Button(action: captureWholePage) { OptionTile(symbol: "text.viewfinder") }
                    .buttonStyle(.plain)
                    .help("Capture the Whole Page")
            }

            // Private windows run no extensions.
            if !state.isPrivate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extensions").font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(state.extensionsInSelectedSpace) { item in
                            ExtensionButton(item: item, profile: state.selectedProfile, currentPage: { tab.browserView })
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.07)))
                                .overlay(alignment: .bottomTrailing) { PinBadge(state: state, item: item) }
                                .contextMenu {
                                    Button("Install in Other Spaces…") {
                                        dismiss()
                                        ExtensionInstaller.shared.ask(toInstall: item, state: state, justInstalled: false)
                                    }
                                    .disabled(state.spacesWithout(extensionID: item.id).isEmpty)
                                }
                        }
                        Button {
                            dismiss()
                            state.newTab(url: "https://chromewebstore.google.com/category/extensions")
                        } label: {
                            Image(systemName: "plus")
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.07)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Add Extensions from the Chrome Web Store")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Settings").font(.headline)
                let isDeveloperMode = state.isDeveloperMode(for: tab.url)
                SettingRow(symbol: "hammer.fill", title: "Developer Mode", isOn: isDeveloperMode) {
                    state.setDeveloperMode(!isDeveloperMode, for: tab.url)
                }
                .disabled(URL(string: tab.url)?.host() == nil)
                SleepRow(tab: tab, standard: state.tabSleepDelay)
                ZoomRow(percent: Int((tab.zoomFactor * 100).rounded()), zoom: zoom)
            }

            if URL(string: tab.url)?.host() != nil {
                SitePermissions(page: tab.browserView)
                Button(action: clearSiteData) {
                    HStack(spacing: 10) {
                        RowIcon(symbol: "trash", tint: nil)
                        Text("Clear Site Data…").fontWeight(.medium).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack {
                Button(action: showCertificate) {
                    Label(isSecure ? "Secure" : "Not Secure", systemImage: isSecure ? "lock.fill" : "lock.open.fill")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.primary.opacity(0.08)))
                        .foregroundStyle(isSecure ? Color.primary : Color.orange)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isSecure)
                .help("Show the Site's Certificate")
                Spacer()
                Button(action: showSiteSettings) {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.primary.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Site Settings")
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var isSecure: Bool {
        URL(string: tab.url)?.scheme == "https"
    }

    private func showCertificate() {
        dismiss()
        SiteCertificate.show(for: tab)
    }

    private func clearSiteData() {
        guard let host = URL(string: tab.url)?.host(), let window = MainWindow.active else { return }
        dismiss()
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear cookies and site data for \(host)?")
        alert.informativeText = String(localized: "You will be signed out of this site, and the data it keeps on this Mac will be deleted, in this space only.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let page = tab.browserView
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            // Chromium may take long to report every kind of data gone, while
            // cookies and storage go at once: the page reloads after at most a second.
            let reload = ReloadOnce(page: page)
            page.clearSiteData { MainActor.assumeIsolated { reload.run() } }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                reload.run()
            }
        }
    }

    /// Chromium's page of permissions and data for the site.
    private func showSiteSettings() {
        guard let url = URL(string: tab.url), let scheme = url.scheme, let host = url.host() else { return }
        dismiss()
        let origin = "\(scheme)://\(host)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        state.newTab(url: "chrome://settings/content/siteDetails?site=\(origin)")
    }

    /// Chromium zooms every page of the site in the profile, so other tabs are read again.
    private func zoom(_ zoom: FLXZoom) {
        tab.zoom(zoom)
        state.tabs.forEach { $0.refreshZoom() }
    }

    private func captureArea() {
        dismiss()
        PageCapture.captureArea(of: tab, state: state)
    }

    private func captureWholePage() {
        dismiss()
        PageCapture.captureWholePage(of: tab, state: state)
    }
}

/// A setting of the site: a round icon, its name and whether it is on. Clicking switches it.
private struct SettingRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.medium)
                    (isOn ? Text("On") : Text("Off")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private final class ReloadOnce: Sendable {
    private let page: FLXBrowserView
    private var isDone = false

    init(page: FLXBrowserView) {
        self.page = page
    }

    func run() {
        guard !isDone else { return }
        isDone = true
        page.reload()
    }
}

/// The certificate of the tab's page and those that issued it, in macOS's own certificate sheet.
@MainActor
enum SiteCertificate {
    static func show(for tab: Tab) {
        let certificates = tab.browserView.certificateChain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard !certificates.isEmpty, let window = MainWindow.active else { return }
        SFCertificatePanel.shared().beginSheet(
            for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, certificates: certificates, showGroup: true
        )
    }
}

/// The permissions sites ask for most, each allowed, blocked, or asked again next time.
private struct SitePermissions: View {
    let page: FLXBrowserView
    @State private var decisions: [String: Bool]

    init(page: FLXBrowserView) {
        self.page = page
        _decisions = State(initialValue: page.sitePermissions.mapValues(\.boolValue))
    }

    private static let shown: [(key: String, symbol: String, title: LocalizedStringKey)] = [
        ("geolocation", "location.fill", "Location"),
        ("notifications", "bell.fill", "Notifications"),
        ("media_stream_camera", "video.fill", "Camera"),
        ("media_stream_mic", "mic.fill", "Microphone"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions").font(.headline)
            ForEach(Self.shown, id: \.key) { permission in
                let allowed = decisions[permission.key]
                let refusedBy = SystemAccess(permissionKey: permission.key).flatMap { $0.isRefused ? $0 : nil }
                ChoiceRow(
                    symbol: permission.symbol,
                    title: permission.title,
                    value: allowed == false ? Text("Block")
                        : refusedBy != nil ? Text("Blocked by macOS")
                        : allowed == true ? Text("Allow") : Text("Ask"),
                    tint: allowed == false ? .red : refusedBy != nil ? .orange : allowed == true ? .accentColor : nil
                ) {
                    Picker(permission.title, selection: binding(for: permission.key)) {
                        Text("Allow").tag(Bool?.some(true))
                        Text("Ask").tag(Bool?.none)
                        Text("Block").tag(Bool?.some(false))
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if let refusedBy {
                        Divider()
                        Button("Open System Settings…") { refusedBy.openSystemSettings() }
                    }
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<Bool?> {
        Binding {
            decisions[key]
        } set: { allowed in
            decisions[key] = allowed
            if let allowed {
                page.setSitePermission(key, allowed: allowed)
            } else {
                page.resetSitePermission(key)
            }
        }
    }
}

/// How long the tab stays loaded unseen, for this tab only.
private struct SleepRow: View {
    @Bindable var tab: Tab
    let standard: TabSleepDelay

    var body: some View {
        ChoiceRow(
            symbol: "moon.zzz.fill",
            title: "Sleep",
            value: tab.sleepDelay.map { Text($0.name) } ?? Text("Default (\(standard.name))"),
            tint: nil
        ) {
            Picker("Sleep", selection: $tab.sleepDelay) {
                Text("Default (\(standard.name))").tag(TabSleepDelay?.none)
                Divider()
                ForEach(TabSleepDelay.allCases) { delay in
                    Text(delay.name).tag(Optional(delay))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .help("Unseen for this long, the page is unloaded to free memory. Pages playing sound or a video stay awake.")
    }
}

/// A setting with a few values: its icon, its name and its value, which a click picks from a menu.
private struct ChoiceRow<Choices: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: Text
    let tint: Color?
    @ViewBuilder let choices: () -> Choices

    var body: some View {
        Menu(content: choices) {
            HStack(spacing: 10) {
                RowIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.medium).lineLimit(1)
                    value.font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

private struct ZoomRow: View {
    let percent: Int
    let zoom: (FLXZoom) -> Void

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(symbol: "plus.magnifyingglass", tint: nil)
            Text("Page Zoom").fontWeight(.medium).lineLimit(1)
            Spacer(minLength: 0)
            Button { zoom(.out) } label: { Image(systemName: "minus").frame(width: 22, height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("Zoom Out")
            Button { zoom(.reset) } label: {
                Text(percent, format: .percent.scale(1)).monospacedDigit().frame(minWidth: 44)
            }
            .buttonStyle(.plain)
            .disabled(percent == 100)
            .help("Actual Size")
            Button { zoom(.in) } label: { Image(systemName: "plus").frame(width: 22, height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("Zoom In")
        }
    }
}

private struct RowIcon: View {
    let symbol: String
    let tint: Color?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint == nil ? Color.primary : Color.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint ?? Color.primary.opacity(0.1)))
    }
}

private struct OptionTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 40)
            .frame(width: 60)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.1)))
            .contentShape(Rectangle())
    }
}

/// Pins the extension next to the address, or takes it away.
private struct PinBadge: View {
    let state: BrowserState
    let item: InstalledExtension

    var body: some View {
        let pinned = state.isPinned(item)
        Button { state.togglePin(item) } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(pinned ? Color.white : Color.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(pinned ? Color.accentColor : Color(nsColor: .windowBackgroundColor)))
        }
        .buttonStyle(.plain)
        .offset(x: 4, y: 4)
        .help(pinned ? "Unpin from the Address Bar" : "Pin to the Address Bar")
    }
}
