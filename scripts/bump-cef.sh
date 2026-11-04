#!/bin/bash
# Pins another CEF version in scripts/cef.env, for example 156.0.15+gcf671c0+chromium-156.0.8078.80,
# with the SHA-256 of its build once the CEF build workflow has published it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/scripts/cef.env"
VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+g[0-9a-f]+\+chromium-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: $0 CEF_VERSION, as the CEF build server names it" >&2
    exit 2
fi
source "$ENV_FILE"

ARCHIVE_NAME="cef_binary_${VERSION}_macosarm64_minimal.tar.bz2"
URL="https://github.com/steeven-th/flux/releases/download/cef-${VERSION%%+*}-$CEF_BUILD/${ARCHIVE_NAME//+/%2B}.sha256"
SHA256="$(curl --fail --silent --location "$URL" | cut -d ' ' -f 1 || true)"

sed -e "s/^CEF_VERSION=.*/CEF_VERSION=\"$VERSION\"/" -e "s/^CEF_SHA256=.*/CEF_SHA256=\"$SHA256\"/" \
    "$ENV_FILE" > "$ENV_FILE.new"
mv "$ENV_FILE.new" "$ENV_FILE"

if [[ -n "$SHA256" ]]; then
    echo "CEF $VERSION ($CEF_BUILD) pinned, scripts/build.sh will download it"
else
    echo "CEF $VERSION pinned, but it has no build yet: run the CEF build workflow, then this again" >&2
fi
