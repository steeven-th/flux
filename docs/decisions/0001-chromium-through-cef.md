# 1. Chromium through CEF

Status: Replaced by [0014](0014-chrome-framework-instead-of-cef.md)

## Context

Flux needs Chrome extensions from the Chrome Web Store and separate profiles with their own logins,
history, passwords and extensions.
It also has to work with Google sign-in, which rejects some embedded browsers.

Most of what makes Chrome a browser (password manager, autofill, extensions, profiles, settings)
lives in the `//chrome` layer of Chromium, above the `//content` rendering layer.

## Decision

Use Chromium through the Chromium Embedded Framework (CEF), at a version pinned in the repository.
Flux started with the standard binary builds published on the CEF build server, and now builds
the same version itself with proprietary codecs (see [0013](0013-cef-built-with-proprietary-codecs.md)).

CEF always runs on the Chrome bootstrap, so profiles, saved passwords and installed extensions are
Chrome's own. Each browser then uses one of two styles:

- **Alloy style** is the only style available when a page is embedded in one of our own views on
  macOS. The page renders, but it is not a Chrome tab: extensions can't see it (a popup asking for
  the active tab gets nothing), and Chrome's UI around it (password bubble, permission prompts) is
  not shown.
- **Chrome style** makes the page a real Chrome tab, but only in windows created by CEF's Views
  framework, which can't be nested in an AppKit view.

Pages use Chrome style. Each page lives in a borderless CEF window, added as a child window of the
Flux window and kept exactly over the page area of the layout. Child windows move with their parent,
so Flux only keeps their size and offset in sync. The window has Chrome's toolbar, hidden, because
Chromium refuses to run an extension's toolbar action without one.

Alloy style is kept for pages that are not tabs, such as extension popups shown under Flux's own
extension buttons. Chromium sees such a popup as a tab, and some extensions lay out differently in
tabs, so Flux makes `chrome.tabs.getCurrent()` return nothing in those pages, as in a real popup.

Extensions without a popup only react to a click on their toolbar button. Flux runs it through the
browser-wide DevTools protocol (`Extensions.triggerAction`), reached over a private pipe rather
than a network port.

Chromium also opens windows of its own, for example after an extension is installed. Flux takes
their pages as tabs and keeps those windows off screen.

## Alternatives considered

- **WebKit (WKWebView + WKWebExtension).** Light and native, but extension support is limited to the
  APIs Safari implements, and many former Arc users expect Chromium compatibility.
- **Electron.** Built on `//content` only. Extensions, password manager, autofill and profiles would
  have to be rebuilt, and Google sign-in is regularly blocked.
- **Tauri.** Uses the system WebKit on macOS, so it has the same limits as WebKit with no Chrome
  extensions.
- **Chromium fork.** Full control, but a multi-hour build and a patch series to rebase on every
  Chromium release. Too much maintenance for a small project.
- **Pages in Alloy style with patched CEF.** Teaching Chromium's extension APIs about Alloy pages
  means building CEF and Chromium ourselves, with the same maintenance cost as a fork.
- **Flux's main window as a CEF Views window.** Avoids child windows, but a Chrome style window
  hosts at most one Chrome style page, which rules out split view.

## Consequences

- Sites, extensions and DevTools behave as in Chrome.
- Focus moves between the page's window and Flux's window, so Flux keeps its window looking
  active and lets the first click in either one act at once.
- Anything drawn over a page (overlays, previews) has to be a window above the page's window.
- Updates follow CEF releases. The pinned version has to be bumped quickly after Chromium security
  releases.
- Standard CEF builds don't ship proprietary codecs (H.264, AAC), so Flux builds CEF itself
  (see [0013](0013-cef-built-with-proprietary-codecs.md)).
- Google services tied to Chrome (Sync, Google Translate, Google Password Manager sync) are not
  available. Translation will use Apple's on-device Translation framework.
- CEF's API is C++, so the app needs an Objective-C++ bridge.
