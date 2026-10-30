import AppKit
import SwiftUI

/// An extension installed in one of Arc's profiles from the Chrome Web Store. Each space keeps
/// those its Arc space had, to install them again.
struct ArcExtension: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    /// In Arc's profile, which may be gone by the time it is shown.
    let iconPath: String?

    var icon: NSImage? {
        iconPath.flatMap { NSImage(contentsOfFile: $0) }
    }

    var storePage: String {
        "https://chromewebstore.google.com/detail/\(id)"
    }

    /// Chromium lists them in the profile's preferences. Those it installed itself, or that were
    /// loaded from a folder, have no store page.
    static func installed(inProfile profile: String) -> [ArcExtension] {
        let folder = ArcLibrary.profileFolder(profile)
        var settings: [String: Any] = [:]
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: folder.appending(path: file)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = (root["extensions"] as? [String: Any])?["settings"] as? [String: Any] else { continue }
            settings.merge(list) { _, new in new }
        }
        return settings.compactMap { id, value -> ArcExtension? in
            guard let entry = value as? [String: Any], entry["from_webstore"] as? Bool == true,
                  let path = entry["path"] as? String else { return nil }
            let directory = path.hasPrefix("/") ? URL(filePath: path) : folder.appending(path: "Extensions/\(path)")
            guard let data = try? Data(contentsOf: directory.appending(path: "manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  manifest["theme"] == nil else { return nil }
            return ArcExtension(id: id, name: name(in: manifest, directory: directory) ?? id, iconPath: iconPath(in: manifest, directory: directory))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Names like "__MSG_appName__" are looked up in the extension's own translations.
    private static func name(in manifest: [String: Any], directory: URL) -> String? {
        guard let name = manifest["name"] as? String else { return nil }
        guard name.hasPrefix("__MSG_"), name.hasSuffix("__") else { return name }
        let key = name.dropFirst(6).dropLast(2).lowercased()
        let locales = [Locale.current.language.languageCode?.identifier, manifest["default_locale"] as? String, "en"].compactMap { $0 }
        for locale in locales {
            guard let data = try? Data(contentsOf: directory.appending(path: "_locales/\(locale)/messages.json")),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (messageKey, value) in messages where messageKey.lowercased() == key {
                if let message = (value as? [String: Any])?["message"] as? String { return message }
            }
        }
        return nil
    }

    private static func iconPath(in manifest: [String: Any], directory: URL) -> String? {
        guard let icons = manifest["icons"] as? [String: String] else { return nil }
        let sizes = icons.keys.compactMap(Int.init).sorted()
        guard let size = sizes.first(where: { $0 >= 32 }) ?? sizes.last, let file = icons[String(size)] else { return nil }
        return directory.appending(path: file).path
    }
}

/// An extension with a button opening its store page in the space, or a check mark once installed.
struct ArcExtensionRow: View {
    let state: BrowserState
    let item: ArcExtension
    let spaceID: UUID

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = item.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "puzzlepiece.extension") }
            }
            .frame(width: 16, height: 16)
            Text(verbatim: item.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if state.isExtensionInstalled(item.id, in: spaceID) {
                Image(systemName: "checkmark").foregroundStyle(.secondary).help("Installed")
            } else {
                Button("Install") {
                    state.selectedSpaceID = spaceID
                    state.newTab(url: item.storePage, in: spaceID)
                }
                .controlSize(.small)
            }
        }
    }
}

/// In the sidebar of a space imported from Arc, its extensions to install again. Chromium signs
/// its list of extensions, so a copied list would be turned off: they are installed again from the
/// Chrome Web Store. Once closed, the card is gone for good.
struct ArcExtensionsCard: View {
    let state: BrowserState

    @State private var asksToHide = false

    var body: some View {
        let spaceID = state.selectedSpaceID
        let extensions = state.arcExtensions(in: spaceID)
        if !extensions.isEmpty, !state.isArcExtensionsCardHidden(in: spaceID) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Extensions from Arc").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { asksToHide = true } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 16, height: 16).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Hide")
                }
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(extensions) { item in
                            ArcExtensionRow(state: state, item: item, spaceID: spaceID)
                        }
                    }
                }
                .frame(height: min(CGFloat(extensions.count) * 26, 130))
            }
            .padding(10)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape.fill(.primary.opacity(0.06)).overlay(shape.strokeBorder(.primary.opacity(0.08)))
            }
            .alert("Hide the extensions from Arc?", isPresented: $asksToHide) {
                Button("Hide") { state.hideArcExtensionsCard(in: spaceID) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This card won't come back. Your extensions are in Flux > Extensions.")
            }
        }
    }
}
