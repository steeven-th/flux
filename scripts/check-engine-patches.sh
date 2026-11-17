#!/bin/bash
# Checks that engine/patches apply to a Chromium version, without a checkout: only the files the
# patches change are downloaded, from chromium.googlesource.com at the version's tag.
#
#   scripts/check-engine-patches.sh [VERSION]   VERSION defaults to the one in scripts/engine.env
#
# Prints one line per patch, and exits with 1 when one doesn't apply, 2 when a file couldn't be
# downloaded.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/engine.env"
VERSION="${1:-$ENGINE_CHROMIUM_VERSION}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
git init --quiet

# The files the patches change, as they are at the tag. A file a patch creates isn't there yet, and
# one Chromium moved or removed answers 404. googlesource.com limits the rate of requests, with 429.
for file in $(grep -h '^--- a/' "$ROOT"/engine/patches/*.patch | sed 's#^--- a/##' | sort -u); do
    mkdir -p "$(dirname "$file")"
    url="https://chromium.googlesource.com/chromium/src/+/refs/tags/$VERSION/$file?format=TEXT"
    for attempt in 1 2 3 4 5 6; do
        status="$(curl --silent --output "$WORK/download" --write-out '%{http_code}' "$url")"
        [[ "$status" == 429 || "$status" == 5* ]] || break
        sleep $(( attempt * 10 ))
    done
    case "$status" in
        200) base64 --decode < "$WORK/download" > "$file" ;;
        404) ;;
        *) echo "Couldn't download $file: HTTP $status" >&2; exit 2 ;;
    esac
    sleep 1
done

failed=0
for patch in "$ROOT"/engine/patches/*.patch; do
    if git apply "$patch" 2> "$WORK/error"; then
        echo "ok      $(basename "$patch")"
    else
        echo "FAILED  $(basename "$patch"): $(head -1 "$WORK/error")"
        failed=1
    fi
done
exit "$failed"
