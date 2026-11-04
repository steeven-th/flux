#!/bin/bash
# Downloads the CEF build pinned in scripts/cef.env into vendor/cef and builds libcef_dll_wrapper.
# The build comes from this repository's releases, made by .github/workflows/cef-build.yml with
# H.264/AAC. Safe to run again: nothing is downloaded or rebuilt when that build is already there.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/cef.env"
CEF_PLATFORM="macosarm64"

VENDOR="$ROOT/vendor"
CEF_DIR="$VENDOR/cef"
ARCHIVE_NAME="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}_minimal.tar.bz2"
ARCHIVE="$VENDOR/$ARCHIVE_NAME"
# The "+" in the version has to be escaped in the URL.
URL="https://github.com/steeven-th/flux/releases/download/cef-${CEF_VERSION%%+*}-$CEF_BUILD/${ARCHIVE_NAME//+/%2B}"
STAMP="$CEF_DIR/.version"
# The build is part of the stamp, so that a new build of the same CEF version replaces the old one.
STAMP_VALUE="$CEF_VERSION $CEF_BUILD"

mkdir -p "$VENDOR"

if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$STAMP_VALUE" ]]; then
    echo "CEF $CEF_VERSION ($CEF_BUILD) already in vendor/cef"
else
    if [[ ! -f "$ARCHIVE" ]] || ! echo "$CEF_SHA256  $ARCHIVE" | shasum -a 256 -c --status; then
        echo "Downloading CEF $CEF_VERSION ($CEF_BUILD)"
        curl --fail --location --progress-bar --output "$ARCHIVE.part" "$URL"
        mv "$ARCHIVE.part" "$ARCHIVE"
        echo "$CEF_SHA256  $ARCHIVE" | shasum -a 256 -c --status || {
            echo "Checksum mismatch for $ARCHIVE_NAME" >&2
            rm -f "$ARCHIVE"
            exit 1
        }
    fi

    echo "Extracting"
    rm -rf "$CEF_DIR"
    mkdir -p "$CEF_DIR"
    tar -xjf "$ARCHIVE" -C "$CEF_DIR" --strip-components 1
    echo "$STAMP_VALUE" > "$STAMP"
    rm -f "$ARCHIVE"
fi

WRAPPER="$CEF_DIR/build/libcef_dll_wrapper/libcef_dll_wrapper.a"
if [[ -f "$WRAPPER" ]]; then
    echo "libcef_dll_wrapper already built"
else
    echo "Building libcef_dll_wrapper"
    # Without an explicit sysroot, CMake can pick the Command Line Tools SDK, which may be newer
    # than the Xcode linker and fail to link.
    cmake -S "$CEF_DIR" -B "$CEF_DIR/build" -DPROJECT_ARCH=arm64 -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" > /dev/null
    cmake --build "$CEF_DIR/build" --target libcef_dll_wrapper --parallel "$(sysctl -n hw.ncpu)"
fi

echo "CEF ready in vendor/cef"
