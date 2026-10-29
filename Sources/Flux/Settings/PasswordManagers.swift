import Foundation
import Observation

/// Whether Chromium's own password manager offers to save passwords and signs in automatically,
/// in one profile.
@MainActor
@Observable
final class ChromiumPasswordManager {
    private static let savingPreference = "credentials_enable_service"
    private static let autoSignInPreference = "credentials_enable_autosignin"

    private(set) var isEnabled = true
    @ObservationIgnored private let profile: FLXProfile

    init(profile: FLXProfile) {
        self.profile = profile
        profile.observePreference(Self.savingPreference) { [weak self] value in
            MainActor.assumeIsolated { self?.isEnabled = (value as? Bool) ?? true }
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        profile.setPreference(Self.savingPreference, boolValue: enabled)
        profile.setPreference(Self.autoSignInPreference, boolValue: enabled)
    }
}

/// Password managers that come as Chrome extensions, known by their Chrome Web Store id.
struct PasswordManagerExtension: Identifiable {
    let id: String
    let name: String

    var storeURL: String {
        "https://chromewebstore.google.com/detail/\(id)"
    }

    var manageURL: String {
        "chrome://extensions/?id=\(id)"
    }

    static let all: [PasswordManagerExtension] = [
        PasswordManagerExtension(id: "nngceckbapebfimnlniiiahkandclblb", name: "Bitwarden"),
        PasswordManagerExtension(id: "aeblfdkhhhdcdjpifhhbdiojplfjncoa", name: "1Password"),
        PasswordManagerExtension(id: "pejdijmoenmkgeppbflobdenhhabjlaj", name: "iCloud Passwords"),
        PasswordManagerExtension(id: "ghmbeldphafepmbegfdlkpapadhbakde", name: "Proton Pass"),
        PasswordManagerExtension(id: "fdjamakpfbbddfjaooikfcpapjohcfmg", name: "Dashlane"),
        PasswordManagerExtension(id: "hdokiejnpimakedhajhdlcegeplioahd", name: "LastPass"),
        PasswordManagerExtension(id: "eiaeiblijfjekdanodkjadfinkhbfgcd", name: "NordPass"),
        PasswordManagerExtension(id: "bfogiafebfohielmmehodmfbbebbbpei", name: "Keeper"),
        PasswordManagerExtension(id: "pnlccmojcmeohlpggmfnbbiapkmbliob", name: "RoboForm"),
        PasswordManagerExtension(id: "kmcfomidfpdkfieipokbalgegidffkal", name: "Enpass"),
    ]
}
