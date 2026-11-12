#!/bin/bash
# Builds the engine pinned in scripts/engine.env: Chrome's framework, renamed EngineCore, with the
# patches in engine/patches and the bridge in engine/src, and H.264/AAC. Run by
# .github/workflows/engine-build.yml: a full build takes 10 to 14 hours on a free GitHub runner.
#
#   scripts/build-engine.sh checkout          Chromium's sources at the pinned version
#   scripts/build-engine.sh build [SECONDS]   applies engine/, then compiles, stops after SECONDS
#                                             with exit code 124, the next call picks up from there
#   scripts/build-engine.sh package           zips the framework and prints the archive's path
#
# ENGINE_BUILD_DIR sets the working folder, ~/engine-build by default.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/engine.env"
BUILD_DIR="${ENGINE_BUILD_DIR:-$HOME/engine-build}"
SRC="$BUILD_DIR/chromium/src"
OUT="out/Engine"

export PATH="$BUILD_DIR/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0

# The commits Chromium 156 pins for these dependencies are gone from their chromium.googlesource.com
# mirrors, so gclient sync fails on them with HTTP 500. They come from the official source tarball
# instead.
TARBALL_DEPS=(third_party/search_engines_data/resources)

write_gclient() {
    local dep custom_deps='"src/third_party/clang-format/script": None,'
    for dep in "${TARBALL_DEPS[@]}"; do
        custom_deps+=" \"src/$dep\": None,"
    done
    mkdir -p "$BUILD_DIR/chromium"
    cat > "$BUILD_DIR/chromium/.gclient" <<GCLIENT
solutions = [{
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git@refs/tags/$ENGINE_CHROMIUM_VERSION",
    "managed": False,
    "deps_file": "DEPS",
    "custom_vars": {"checkout_pgo_profiles": False, "source_tarball": False, "siso_version": "latest"},
    "custom_deps": {$custom_deps},
}]
GCLIENT
}

extract_tarball_deps() {
    local name="chromium-$ENGINE_CHROMIUM_VERSION.tar.xz"
    local url="https://commondatastorage.googleapis.com/chromium-browser-official/$name"
    local expected
    expected="$(curl --fail --silent --show-error --location "$url.hashes" | awk '$1 == "sha256" { print $2 }')"
    curl --fail --silent --show-error --location --output "$BUILD_DIR/$name" "$url"
    if ! echo "$expected  $BUILD_DIR/$name" | shasum -a 256 -c --status; then
        echo "Checksum mismatch for $name" >&2
        exit 1
    fi
    tar -xJf "$BUILD_DIR/$name" -C "$SRC" --strip-components 1 \
        "${TARBALL_DEPS[@]/#/chromium-$ENGINE_CHROMIUM_VERSION/}"
    rm "$BUILD_DIR/$name"
}

checkout() {
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    if [[ ! -d depot_tools ]]; then
        git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
    fi
    # Fails when called through a relative path.
    "$BUILD_DIR/depot_tools/ensure_bootstrap"
    local attempt
    for attempt in 1 2 3; do
        write_gclient
        cd "$BUILD_DIR/chromium"
        if gclient sync --nohooks --no-history --jobs 16; then
            break
        fi
        if (( attempt == 3 )); then
            exit 1
        fi
        # chromium.googlesource.com sometimes answers HTTP 500 for minutes. A checkout without
        # history that failed halfway can't be completed, so start over.
        echo "Checkout failed, retrying in 2 minutes" >&2
        cd "$BUILD_DIR"
        rm -rf "$BUILD_DIR/chromium"
        sleep 120
    done
    extract_tarball_deps
    cd "$BUILD_DIR/chromium"
    gclient runhooks
}

# The sources are restored untouched in every job, and engine/ goes on top of them. Files that come
# out the same as in the job before get back the mtime they had then, or siso would rebuild
# everything that depends on them.
apply_engine() {
    cd "$SRC"
    local patch
    for patch in "$ROOT"/engine/patches/*.patch; do
        git apply "$patch"
    done
    rsync -a --delete "$ROOT/engine/src/" engine_core/
    mkdir -p "$OUT"
    {
        grep -h '^+++ b/' "$ROOT"/engine/patches/*.patch | sed 's|^+++ b/||'
        find engine_core -type f
    } | sort -u | python3 -c '
import hashlib, os, sys
manifest = sys.argv[1]
known = {}
if os.path.exists(manifest):
    for line in open(manifest):
        path, digest, mtime = line.rstrip("\n").rsplit(" ", 2)
        known[path] = (digest, int(mtime))
lines = []
for path in sys.stdin.read().splitlines():
    digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if path in known and known[path][0] == digest:
        os.utime(path, ns=(known[path][1], known[path][1]))
    lines.append(f"{path} {digest} {os.stat(path).st_mtime_ns}\n")
open(manifest, "w").writelines(lines)
' "$OUT/engine-mtimes.txt"
    # Chromium only plays DRM protected media, as on Netflix, with Widevine, which only Chrome
    # branded builds turn on by default. The component updater then downloads its CDM.
    local args
    args="$(cat <<ARGS
is_debug = false
is_component_build = false
dcheck_always_on = false
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
enable_dsyms = false
target_cpu = "arm64"
proprietary_codecs = true
ffmpeg_branding = "Chrome"
enable_widevine = true
ARGS
)"
    # A resumed build keeps the build folder of the one before, which may have other arguments.
    if [[ ! -f "$OUT/build.ninja" || "$(cat "$OUT/args.gn" 2>/dev/null)" != "$args" ]]; then
        printf '%s\n' "$args" > "$OUT/args.gn"
        gn gen "$OUT"
    fi
}

build() {
    apply_engine
    cd "$SRC"
    if [[ -n "${1:-}" ]]; then
        # siso stops cleanly on SIGINT and the next build resumes from there.
        gtimeout --signal INT --kill-after 10m "$1" autoninja -C "$OUT" chrome_framework
    else
        autoninja -C "$OUT" chrome_framework
    fi
}

package() {
    local archive="$BUILD_DIR/EngineCore-$ENGINE_CHROMIUM_VERSION-$ENGINE_BUILD-arm64.zip"
    rm -f "$archive"
    ditto -c -k --keepParent "$SRC/$OUT/EngineCore.framework" "$archive"
    echo "$archive"
}

case "${1:-}" in
    checkout) checkout ;;
    build) build "${2:-}" ;;
    package) package ;;
    *) echo "Usage: $0 checkout | build [SECONDS] | package" >&2; exit 2 ;;
esac
