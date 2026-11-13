# 17. Releases from Conventional Commits

Status: Accepted

## Context

Flux needs version numbers, release notes and a download for each version. Commits already follow
Conventional Commits, so the type of each change is written down when it is made. Writing the
notes by hand would repeat that work, and tagging and packaging by hand is easy to get wrong.

Flux has no Apple Developer ID yet. A Mac app signed without one can't be notarized, so Gatekeeper
blocks it the first time it opens.

## Decision

Versions follow Semantic Versioning, starting at 0.1.0, with tags such as `v0.1.0`. The engine
keeps its own `engine-*` tags.

The release-please action (`.github/workflows/release.yml`) keeps a release pull request up to date
on each push to `main`. It works out the next version from the commits, writes it in
`project.yml`, and adds the changes to `CHANGELOG.md`: `feat` under New, `perf` under Faster, `fix`
under Fixed, `style` and `refactor` under Smaller. Other types stay out of the notes. Nothing is
released until the maintainer merges that pull request. Merging it tags the version and publishes
the notes as a GitHub release.

The same workflow then builds Flux with `scripts/package.sh`, signs it with a self-signed
certificate kept in the repository's secrets, and attaches `Flux.dmg` to the release. The
certificate stays the same from one version to the next, so Chromium keeps its secret in the
keychain (see [0008](0008-system-keychain-when-signed.md)) and macOS doesn't ask for it again after
an update. Until Flux has a Developer ID, the website explains how to open it the first time.

## Alternatives considered

- **Releases by hand.** Full control over the notes, but each release takes a long checklist, and
  versions and notes drift apart.
- **semantic-release.** Releases on every push that has a `feat` or a `fix`, with no step where the
  maintainer decides. It also comes from the npm world and needs Node in the repository.
- **Ad hoc signature.** Nothing to keep secret, but the signature changes with every build, and
  macOS would ask for the keychain after every update.
- **Apple Developer ID and notarization.** No warning at first launch, but it costs 99 USD a year.
  It replaces the self-signed certificate once Flux has enough users to justify it.

## Consequences

- Commit subjects of type `feat`, `fix` and `perf` are what users read in the release notes.
- Losing the certificate or its password means a new signature, and one keychain prompt for every
  user after the next update. [docs/releasing.md](../releasing.md) says where it is kept.
- People installing Flux go through System Settings > Privacy & Security once.
