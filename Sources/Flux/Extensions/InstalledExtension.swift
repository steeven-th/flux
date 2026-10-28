import AppKit

struct InstalledExtension: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage?
    /// Page shown when the toolbar icon is clicked. Extensions without one react to the click
    /// through chrome.action.onClicked, which only Chrome can send.
    let popupURL: String?
}

extension InstalledExtension {
    /// Reads an extension from the folder Chromium unpacked it into.
    init?(id: String, folder: URL) {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let action = (manifest["action"] ?? manifest["browser_action"]) as? [String: Any]
        let rawName = manifest["name"] as? String ?? id

        self.id = id
        name = Self.localized(rawName, in: folder, defaultLocale: manifest["default_locale"] as? String)
        icon = Self.iconPath(in: action?["default_icon"] ?? manifest["icons"])
            .flatMap { NSImage(contentsOf: folder.appending(path: $0)) }
        popupURL = (action?["default_popup"] as? String).map { "chrome-extension://\(id)/\($0)" }
    }

    /// Resolves "__MSG_name__" from the extension's message catalogs.
    private static func localized(_ value: String, in folder: URL, defaultLocale: String?) -> String {
        guard value.hasPrefix("__MSG_"), value.hasSuffix("__") else { return value }
        let key = value.dropFirst(6).dropLast(2).lowercased()
        let locales: [String?] = [Locale.current.identifier, Locale.current.language.languageCode?.identifier, defaultLocale]
        for locale in locales.compactMap({ $0 }) {
            let url = folder.appending(path: "_locales/\(locale)/messages.json")
            guard let data = try? Data(contentsOf: url),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let entry = messages.first { $0.key.lowercased() == key }?.value as? [String: Any]
            if let message = entry?["message"] as? String {
                return message
            }
        }
        return value
    }

    /// `icons` is either a path or a dictionary of paths keyed by pixel size.
    private static func iconPath(in icons: Any?) -> String? {
        if let path = icons as? String {
            return path
        }
        guard let sizes = icons as? [String: String] else { return nil }
        let sorted = sizes.compactMap { key, path in Int(key).map { ($0, path) } }.sorted { $0.0 < $1.0 }
        return (sorted.first { $0.0 >= 32 } ?? sorted.last)?.1
    }
}
