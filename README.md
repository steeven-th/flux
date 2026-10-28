# Flux

A macOS browser with a sidebar, folders and spaces that stay apart. Each space has its own
logins, history, passwords and extensions, so work, personal and client browsing live in one
window without leaking into each other.

Flux runs on Chromium through the Chromium Embedded Framework, so sites and Chrome extensions work
as they do in Chrome. The app itself is native Swift.

Flux is at an early stage and not usable yet.

## Requirements

- macOS 14 or later on Apple silicon
- Xcode 16 or later
- XcodeGen and CMake: `brew install xcodegen cmake`

## Documentation

Architecture decisions are recorded in [docs/decisions](docs/decisions).
