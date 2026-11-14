# 18. Updates with Sparkle

Status: Accepted

## Context

Flux is downloaded from its website, outside the App Store, so nothing tells people a new version
is out. A browser that stays on an old version also stays on an old Chromium, with its security
holes. Installing a new DMG by hand also means going through System Settings > Privacy & Security
again, since Flux has no Apple Developer ID (see [0017](0017-releases-from-conventional-commits.md)).

## Decision

Flux updates itself with Sparkle 2, added as a Swift package.

- Flux checks `https://flux-browser.com/appcast.xml` once a day, from the first launch. The website
  builds that feed from the GitHub releases, along with the release notes.
- A version found by the daily check doesn't open a window. The Check for Updates item of the Flux
  menu becomes Update Available, with a badge, as in Arc. Choosing it shows the notes and installs
  the version.
- Each `Flux.dmg` is signed with an EdDSA key. The release workflow signs it with the private key,
  kept in the repository's secrets, and attaches the signature to the release as
  `Flux.dmg.sparkle`. The public key is in Flux's `Info.plist`. Sparkle installs nothing whose
  signature doesn't match, and checks that the new app is signed with the same certificate as the
  one it replaces.
- `CFBundleVersion` is the version itself, which release-please writes in `project.yml`. Sparkle
  compares it with the versions in the feed.
- Debug builds don't check, so a development build never replaces itself with a released one.

## Alternatives considered

- **A check of the GitHub releases, and a link to the download.** No dependency, but people would
  still replace the app by hand and open it anyway each time.
- **The feed as a release asset on GitHub.** No website involved, but the address of the feed
  would be tied to where the repository lives, and it can't change once versions use it.
- **Homebrew cask only.** Updates for people who use Homebrew, nothing for the others.

## Consequences

- Updates downloaded by Flux aren't quarantined, so only the first install goes through Privacy &
  Security.
- Losing the private key means users of the versions out there can't update anymore, and have to
  download Flux again. [docs/releasing.md](../releasing.md) says where it is kept.
- The feed's address can't change without a redirect from the old one.
