# 1. Chromium through CEF

Status: Accepted

## Context

Flux needs Chrome extensions from the Chrome Web Store, a built-in password manager for people who
don't use a third-party one, and separate profiles with their own logins, history and extensions.
It also has to work with Google sign-in, which rejects some embedded browsers.

Most of what makes Chrome a browser (password manager, autofill, extensions, profiles, settings)
lives in the `//chrome` layer of Chromium, above the `//content` rendering layer.

## Decision

Use Chromium through the Chromium Embedded Framework (CEF). Start with the standard binary builds
published on the CEF build server and pin the version in the repository.

CEF always runs on the Chrome bootstrap, so profiles, saved passwords and installed extensions are
Chrome's own. Each browser then uses one of two styles:

- **Alloy style** is the only style available when a page is embedded in one of our own views on
  macOS. Pages render and Chrome features run underneath, but Chrome's UI around them (password
  save bubble, autofill dropdown, permission prompts, extension popups) is not shown. Flux has to
  provide that UI itself.
- **Chrome style** brings that UI, but only in windows created by CEF's own Views framework, which
  don't fit inside an AppKit layout.

Flux embeds pages in Alloy style. The first prototype has to confirm which Chrome features keep
working there (password saving and filling, extension popups) and how much UI has to be rebuilt.

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
