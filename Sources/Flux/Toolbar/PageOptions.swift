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

            VStack(alignment: .leading, spacing: 8) {
                Text("Extensions").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(state.extensionsInSelectedSpace) { item in
                        ExtensionButton(item: item, profile: state.selectedProfile, currentPage: { tab.browserView })
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.07)))
                            .overlay(alignment: .bottomTrailing) { PinBadge(state: state, item: item) }
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Settings").font(.headline)
                let isDeveloperMode = state.isDeveloperMode(for: tab.url)
                SettingRow(symbol: "hammer.fill", title: "Developer Mode", isOn: isDeveloperMode) {
                    state.setDeveloperMode(!isDeveloperMode, for: tab.url)
                }
                .disabled(URL(string: tab.url)?.host() == nil)
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

    /// The certificate and those that issued it, in macOS's own certificate sheet.
    private func showCertificate() {
        let certificates = tab.browserView.certificateChain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard !certificates.isEmpty, let window = NSApp.windows.first(where: { $0 is MainWindow }) else { return }
        dismiss()
        SFCertificatePanel.shared().beginSheet(
            for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, certificates: certificates, showGroup: true
        )
    }

    /// Chromium's page of permissions and data for the site.
    private func showSiteSettings() {
        guard let url = URL(string: tab.url), let scheme = url.scheme, let host = url.host() else { return }
        dismiss()
        let origin = "\(scheme)://\(host)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        state.newTab(url: "chrome://settings/content/siteDetails?site=\(origin)")
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
