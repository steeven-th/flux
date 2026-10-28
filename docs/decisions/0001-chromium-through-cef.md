# 1. Chromium through CEF

Status: Accepted

## Context

Flux needs Chrome extensions from the Chrome Web Store, a built-in password manager for people who
don't use a third-party one, and separate profiles with their own logins, history and extensions.
It also has to work with Google sign-in, which rejects some embedded browsers.

Most of what makes Chrome a browser (password manager, autofill, extensions, profiles, settings)
lives in the `//chrome` layer of Chromium, above the `//content` rendering layer.

## Decision

Use Chromium through the Chromium Embedded Framework (CEF) with the Chrome style runtime, which
includes the `//chrome` layer. Start with the standard binary builds published on the CEF build
server and pin the version in the repository.

## Alternatives considered

- **WebKit (WKWebView + WKWebExtension).** Light and native, but extension support is limited to the
  APIs Safari implements, and many former Arc users expect Chromium compatibility.
- **Electron.** Built on `//content` only. Extensions, password manager, autofill and profiles would
  have to be rebuilt, and Google sign-in is regularly blocked.
- **Tauri.** Uses the system WebKit on macOS, so it has the same limits as WebKit with no Chrome
  extensions.
- **Chromium fork.** Full control, but a multi-hour build and a patch series to rebase on every
  Chromium release. Too much maintenance for a small project.

## Consequences

- Sites, extensions and DevTools behave as in Chrome.
- Updates follow CEF releases. The pinned version has to be bumped quickly after Chromium security
  releases.
- Standard CEF builds don't ship proprietary codecs (H.264, AAC). Some videos won't play until we
  decide whether to build CEF ourselves.
- Google services tied to Chrome (Sync, Google Translate, Google Password Manager sync) are not
  available. Translation will use Apple's on-device Translation framework.
- CEF's API is C++, so the app needs an Objective-C++ bridge.
