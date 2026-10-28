#!/bin/bash
# Downloads the pinned CEF binary distribution into vendor/cef and builds libcef_dll_wrapper.
# Safe to run again: nothing is downloaded or rebuilt when the pinned version is already there.
set -euo pipefail

CEF_VERSION="156.0.14+g4fa4ab5+chromium-156.0.8078.48"
CEF_SHA1="7359a9d293dd5c480bec3f18b762731b483b0e13"
CEF_PLATFORM="macosarm64"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
CEF_DIR="$VENDOR/cef"
ARCHIVE_NAME="cef_binary_${CEF_VERSION}_${CEF_PLATFORM}_minimal.tar.bz2"
ARCHIVE="$VENDOR/$ARCHIVE_NAME"
# The "+" in the version has to be escaped in the URL.
URL="https://cef-builds.spotifycdn.com/${ARCHIVE_NAME//+/%2B}"
STAMP="$CEF_DIR/.version"

mkdir -p "$VENDOR"

if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$CEF_VERSION" ]]; then
    echo "CEF $CEF_VERSION already in vendor/cef"
else
    if [[ ! -f "$ARCHIVE" ]] || ! echo "$CEF_SHA1  $ARCHIVE" | shasum -a 1 -c --status; then
        echo "Downloading CEF $CEF_VERSION"
        curl --fail --location --progress-bar --output "$ARCHIVE.part" "$URL"
        mv "$ARCHIVE.part" "$ARCHIVE"
        echo "$CEF_SHA1  $ARCHIVE" | shasum -a 1 -c --status || {
            echo "Checksum mismatch for $ARCHIVE_NAME" >&2
            rm -f "$ARCHIVE"
            exit 1
        }
    fi

    echo "Extracting"
    rm -rf "$CEF_DIR"
    mkdir -p "$CEF_DIR"
    tar -xjf "$ARCHIVE" -C "$CEF_DIR" --strip-components 1
    echo "$CEF_VERSION" > "$STAMP"
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
