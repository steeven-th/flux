import Foundation
import GRDB

/// Brings a profile's history, passwords and sign-ins from another browser into a Flux profile
/// that Chromium hasn't opened yet. Arc and Dia run the same Chromium as Flux, so their databases
/// are used as they are, with each password and cookie protected again with Flux's key.
@MainActor
enum ProfileTransfer {
    struct Keys {
        let source: ChromiumSafeStorage
        let flux: ChromiumSafeStorage
    }

    private static var loadedKeys: [ImportSource: Keys?] = [:]

    /// Read once per browser: macOS asks the user's password to let Flux read its key. Nil when
    /// Flux keeps no key in the keychain itself, since passwords would be protected with
    /// Chromium's fixed one.
    static func keys(for source: ImportSource) -> Keys? {
        if let loaded = loadedKeys[source] { return loaded }
        var keys: Keys?
        let item = source.keychainItem
        if FLXEngine.usesSystemKeychain, let key = ChromiumSafeStorage.of(service: item.service, account: item.account),
           let flux = ChromiumSafeStorage.flux() {
            keys = Keys(source: key, flux: flux)
        }
        loadedKeys[source] = .some(keys)
        return keys
    }

    /// Without keys, only the history comes: it isn't protected.
    static func transfer(from source: URL, to folder: URL, keys: Keys?) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        copy("History", from: source, to: folder)
        guard let keys else { return }
        if copy("Login Data", from: source, to: folder) {
            protectAgain(table: "logins", column: "password_value", in: folder.appending(path: "Login Data"), keys: keys)
        }
        if copy("Cookies", from: source, to: folder) {
            protectAgain(table: "cookies", column: "encrypted_value", in: folder.appending(path: "Cookies"), keys: keys)
        }
    }

    /// With its journal: the browser may be writing, and opening the copy rolls an unfinished write
    /// back.
    @discardableResult
    private static func copy(_ name: String, from source: URL, to folder: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.appending(path: name).path) else { return false }
        for file in [name, "\(name)-journal"] where manager.fileExists(atPath: source.appending(path: file).path) {
            try? manager.removeItem(at: folder.appending(path: file))
            guard (try? manager.copyItem(at: source.appending(path: file), to: folder.appending(path: file))) != nil else { return false }
        }
        return true
    }

    /// Values that don't open with the browser's key would be unreadable with Flux's: their rows go.
    private static func protectAgain(table: String, column: String, in file: URL, keys: Keys) {
        guard let database = try? DatabaseQueue(path: file.path) else { return }
        try? database.write { db in
            // SQLite names rowid after the table's integer primary key, when it has one.
            let rows = try Row.fetchAll(db, sql: "SELECT rowid AS flux_row, \(column) FROM \(table) WHERE length(\(column)) > 0")
            for row in rows {
                guard let id = row["flux_row"] as Int64?, let value = row[column] as Data? else { continue }
                if let plain = keys.source.decrypt(value) {
                    try db.execute(sql: "UPDATE \(table) SET \(column) = ? WHERE rowid = ?", arguments: [keys.flux.encrypt(plain), id])
                } else {
                    try db.execute(sql: "DELETE FROM \(table) WHERE rowid = ?", arguments: [id])
                }
            }
        }
    }
}
