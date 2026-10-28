# 5. Xcode project generated with XcodeGen

Status: Proposed

## Context

A CEF app on macOS is more than one executable. The bundle needs the CEF framework in
`Contents/Frameworks` and several helper apps (main, GPU, renderer, plugin, alerts) that Chromium
launches as subprocesses. The project must build from the command line and still be easy to debug
in Xcode, across Swift and Objective-C++.

## Decision

Describe the project in `project.yml` and generate the Xcode project with XcodeGen. The generated
`.xcodeproj` is not committed.

- A script downloads the pinned CEF binary distribution into `vendor/cef` and builds
  `libcef_dll_wrapper` with CMake.
- Helper apps are regular targets, embedded by a copy phase.
- `xcodebuild` is used for command line and CI builds.

## Alternatives considered

- **Swift Package Manager with a bundling script.** No generated project, but the app bundle and
  helpers have to be assembled by hand, and Xcode debugging of the final app is less direct.
- **CMake for everything.** This is how the CEF samples are built, but Swift support in CMake is
  limited and less familiar to Swift contributors.
- **Committed `.xcodeproj`.** No extra tool, but project files merge badly.

## Consequences

- Contributors need XcodeGen and CMake (`brew install xcodegen cmake`).
- Changing targets or build settings means editing `project.yml` and regenerating.
