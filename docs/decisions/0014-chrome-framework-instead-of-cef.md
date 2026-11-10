# 14. Chrome's framework instead of CEF

Status: Accepted. Replaces [0001](0001-chromium-through-cef.md) and
[0013](0013-cef-built-with-proprietary-codecs.md).

## Context

CEF gave Flux Chrome's profiles, extensions and password manager, but its pages are only real
Chrome tabs in windows made by CEF's Views framework. Flux kept one such window per page, laid
over its own window, and worked around what CEF leaves out:

- a hidden Chrome toolbar, without which extensions' toolbar actions don't run, and actions run
  through the DevTools protocol
- Chrome's own windows, opened after an extension install for example, hidden and their pages
  taken back
- a helper process injecting scripts for media and picture-in-picture
- DevTools without device mode, replaced by a responsive mode of Flux's own (0007)
- the Chrome Web Store asking to switch to Chrome

Since then, several Arc-like browsers embed Chrome's framework itself, with a layer of their own,
and get all of this from Chrome. Sailfish publishes such a layer, EngineCore, under the Apache
License 2.0: 20 patches to Chromium and an Objective-C bridge. A trial of Flux on its prebuilt
framework passed for profiles, extensions, the Web Store, popups and their badges, and video. It
lacked docked DevTools with device mode, which need changes to Chromium.

## Decision

Flux builds EngineCore itself, from Sailfish's `engine/` with patches of its own, on GitHub
Actions, and runs on it instead of CEF. Pages are views of Flux's window. DevTools dock next to the
page in the same window, hosted by the bridge, with Chrome's device mode. See
[docs/engine.md](../engine.md).

## Alternatives considered

- **Staying on CEF and patching it.** Each gap needs its own patch, and CEF's own patches take
  parts of Chrome away. The workarounds above would stay.
- **Sailfish's prebuilt framework.** No build to run, but no way to change the engine, and
  security updates follow Sailfish's pace.
- **Ardia's engine.** Built on Helium's patches, which are GPL-3.0, and Ardia's contributors give
  its owner the right to relicense their work.
- **Forking a whole browser, Sailfish or Ardia.** Flux would lose its own interface, and follow
  upstream changes made at a pace of dozens of commits a day.
