#!/bin/bash
# Downloads the engine pinned in scripts/engine.env into vendor/enginecore. It comes from this
# repository's releases, made by .github/workflows/engine-build.yml. Safe to run again: nothing is
# downloaded when that build is already there.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/engine.env"

VENDOR="$ROOT/vendor"
ENGINE_DIR="$VENDOR/enginecore"
ARCHIVE_NAME="EngineCore-$ENGINE_CHROMIUM_VERSION-$ENGINE_BUILD-arm64.zip"
ARCHIVE="$VENDOR/$ARCHIVE_NAME"
URL="https://github.com/steeven-th/flux/releases/download/engine-$ENGINE_CHROMIUM_VERSION-$ENGINE_BUILD/$ARCHIVE_NAME"
STAMP="$ENGINE_DIR/.version"
STAMP_VALUE="$ENGINE_CHROMIUM_VERSION $ENGINE_BUILD"

if [[ -z "$ENGINE_SHA256" ]]; then
    echo "scripts/engine.env has no ENGINE_SHA256 yet: the engine build isn't published" >&2
    exit 1
fi

mkdir -p "$VENDOR"

if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$STAMP_VALUE" ]]; then
    echo "Engine $STAMP_VALUE already in vendor/enginecore"
    exit 0
fi

if [[ ! -f "$ARCHIVE" ]] || ! echo "$ENGINE_SHA256  $ARCHIVE" | shasum -a 256 -c --status; then
    echo "Downloading the engine $STAMP_VALUE"
    curl --fail --location --progress-bar --output "$ARCHIVE.part" "$URL"
    mv "$ARCHIVE.part" "$ARCHIVE"
    echo "$ENGINE_SHA256  $ARCHIVE" | shasum -a 256 -c --status || {
        echo "Checksum mismatch for $ARCHIVE_NAME" >&2
        rm -f "$ARCHIVE"
        exit 1
    }
fi

echo "Extracting"
rm -rf "$ENGINE_DIR"
mkdir -p "$ENGINE_DIR"
ditto -x -k "$ARCHIVE" "$ENGINE_DIR"
echo "$STAMP_VALUE" > "$STAMP"
rm -f "$ARCHIVE"
echo "Engine ready in vendor/enginecore"
