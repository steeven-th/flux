# 8. Chromium's key in the keychain when Flux is signed

Status: Proposed

## Context

Chromium protects saved passwords and cookies with a key derived from a secret it keeps in the
macOS keychain. The keychain lets an app read its items again without asking only while its
signature stays the same. An ad hoc signature changes with every build, so each build would bring
a keychain prompt.

Flux used to pass `use-mock-keychain` to Chromium for that reason. Chromium then derives the key
from a fixed, public secret, which leaves passwords and cookies readable by anyone with the files.
Importing passwords from Arc made that a real problem.

## Decision

Chromium keeps its secret in the keychain when Flux is signed with a certificate, which keeps the
same identity from one build to the next. `scripts/build.sh` signs with an Apple Development
certificate when one is installed. Ad hoc builds keep the fixed secret.

The import from Arc reads Arc's secret, with the user's permission, and makes Flux's own when
Chromium hasn't yet, the way Chromium makes it.

## Alternatives considered

- **Always the keychain.** Contributors without a certificate would get a prompt at every build.
- **Always the fixed secret.** Simple, but passwords and cookies would be as good as plain text.

## Consequences

- Passwords and cookies saved by an ad hoc build can't be read by a signed one, and the other way
  round. A profile moves from one to the other by signing in again.
- Passwords, sign-ins and history come from Arc only in signed builds.
