# 2. Native macOS app in Swift

Status: Accepted

## Context

The browser UI (sidebar, command bar, split view, small preview windows) has to feel native on
macOS: vibrancy, gestures, standard keyboard handling and window behavior. Web content is drawn by
CEF in native views, so any UI drawn above the page also has to be native.

## Decision

Write the app in Swift. Use AppKit for windows, view hierarchy and anything that sits next to CEF
views, and SwiftUI for self-contained UI such as the sidebar content, settings and command bar.

- macOS 15 or later, Apple silicon only. It started at macOS 14, and moved to 15 for the
  Translation framework's batch sessions, which page translation needs.
- Swift 6 language mode. CEF runs its UI thread on the main thread on macOS, so browser code can be
  `@MainActor` and strict concurrency should not get in the way. To be confirmed in the first
  prototype.
- A thin Objective-C++ bridge wraps the CEF C++ API and exposes plain Objective-C types to Swift.
  It is split by concern (browser, profiles, downloads, extensions, DevTools) rather than kept in
  one file.

## Alternatives considered

- **Web UI (TypeScript) in a separate view.** Familiar tooling, but HTML can't be drawn above CEF
  views, and every interaction would cross a bridge.
- **React Native for macOS.** Allows TypeScript for the UI, but adds a JavaScript runtime and a
  toolchain on top of CEF and AppKit.

## Consequences

- macOS only for now. A Windows or Linux version would need a new UI layer.
- Apple frameworks are directly available: Translation, Spotlight, Keychain, LocalAuthentication.
