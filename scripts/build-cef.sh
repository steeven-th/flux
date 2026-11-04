#!/bin/bash
# Builds the CEF version pinned in scripts/cef.env from source, with H.264/AAC, which the CEF
# build server leaves out. Run by .github/workflows/cef-build.yml: a full build takes 10 to 14
# hours on a free GitHub runner and about 80 GB of disk.
#
#   scripts/build-cef.sh checkout          Chromium and CEF sources, then the GN build files
#   scripts/build-cef.sh build [SECONDS]   compiles, stops after SECONDS with exit code 124,
#                                          the next call picks up where it stopped
#   scripts/build-cef.sh package           writes the minimal distribution and prints its path
#
# CEF_BUILD_DIR sets the working folder, ~/cef-build by default.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/cef.env"
BUILD_DIR="${CEF_BUILD_DIR:-$HOME/cef-build}"
SRC="$BUILD_DIR/chromium/src"
OUT="out/Release_GN_arm64"

# The version names the CEF commit and the Chromium branch it belongs to:
# 156.0.14+g4fa4ab5+chromium-156.0.8078.48 is commit 4fa4ab5 on branch 8078.
if [[ ! "$CEF_VERSION" =~ \+g([0-9a-f]+)\+chromium-([0-9]+\.[0-9]+\.([0-9]+)\.[0-9]+)$ ]]; then
    echo "Unexpected CEF_VERSION: $CEF_VERSION" >&2
    exit 1
fi
CEF_COMMIT="${BASH_REMATCH[1]}"
CHROMIUM_VERSION="${BASH_REMATCH[2]}"
CEF_BRANCH="${BASH_REMATCH[3]}"

export PATH="$BUILD_DIR/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0
export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome \
symbol_level=0 blink_symbol_level=0 v8_symbol_level=0 enable_dsyms=false"

# The commits Chromium 156 pins for these dependencies are gone from their chromium.googlesource.com
# mirrors, so gclient sync fails on them with HTTP 500. They come from the official source tarball
# instead.
TARBALL_DEPS=(third_party/search_engines_data/resources)

# automate-git.py keeps an existing .gclient, which is the only way to leave out a dependency.
# clang-format/script is gone as well, and the build does not need it: the clang-format binary
# comes from buildtools.
write_gclient() {
    local dep custom_deps='"src/third_party/clang-format/script": None,'
    for dep in "${TARBALL_DEPS[@]}"; do
        custom_deps+=" \"src/$dep\": None,"
    done
    mkdir -p "$BUILD_DIR/chromium"
    cat > "$BUILD_DIR/chromium/.gclient" <<EOF
solutions = [{
    "name": "src",
    "url": "https://chromium.googlesource.com/chromium/src.git@$CHROMIUM_VERSION",
    "managed": False,
    "deps_file": "DEPS",
    "custom_vars": {"checkout_pgo_profiles": True, "source_tarball": False, "siso_version": "latest"},
    "custom_deps": {$custom_deps},
    "safesync_url": "",
}]
EOF
}

extract_tarball_deps() {
    local name="chromium-$CHROMIUM_VERSION.tar.xz"
    local url="https://commondatastorage.googleapis.com/chromium-browser-official/$name"
    local expected
    expected="$(curl --fail --silent --show-error --location "$url.hashes" | awk '$1 == "sha256" { print $2 }')"
    curl --fail --silent --show-error --location --output "$BUILD_DIR/$name" "$url"
    if ! echo "$expected  $BUILD_DIR/$name" | shasum -a 256 -c --status; then
        echo "Checksum mismatch for $name" >&2
        exit 1
    fi
    tar -xJf "$BUILD_DIR/$name" -C "$SRC" --strip-components 1 \
        "${TARBALL_DEPS[@]/#/chromium-$CHROMIUM_VERSION/}"
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
    # automate-git.py changes from one CEF branch to the next.
    curl --fail --silent --show-error --location --output automate-git.py \
        "https://raw.githubusercontent.com/chromiumembedded/cef/$CEF_BRANCH/tools/automate/automate-git.py"
    local attempt
    for attempt in 1 2 3; do
        write_gclient
        if python3 automate-git.py --download-dir="$BUILD_DIR" --depot-tools-dir="$BUILD_DIR/depot_tools" \
            --branch="$CEF_BRANCH" --checkout="$CEF_COMMIT" --arm64-build --no-chromium-history \
            --no-depot-tools-update --with-pgo-profiles --no-debug-build --no-build --no-distrib; then
            break
        fi
        if (( attempt == 3 )); then
            exit 1
        fi
        # chromium.googlesource.com sometimes answers HTTP 500 for minutes. Without history,
        # automate-git.py does not complete a checkout that failed halfway, so start over.
        echo "Checkout failed, retrying in 2 minutes" >&2
        rm -rf "$BUILD_DIR/chromium"
        sleep 120
    done
    extract_tarball_deps
    cd "$SRC/cef"
    python3 tools/gclient_hook.py
}

build() {
    cd "$SRC"
    # make_distrib takes the framework out of cefclient.app.
    if [[ -n "${1:-}" ]]; then
        # siso stops cleanly on SIGINT and the next build resumes from there.
        gtimeout --signal INT --kill-after 10m "$1" autoninja -C "$OUT" cefclient
    else
        autoninja -C "$OUT" cefclient
    fi
}

package() {
    local dist="$SRC/cef/binary_distrib"
    local archive="$dist/cef_binary_${CEF_VERSION}_macosarm64_minimal.tar.bz2"
    rm -rf "$dist"
    cd "$SRC/cef/tools"
    # --allow-partial because there is no Debug build, --no-symbols because dSYMs are turned off.
    CEF_ARCHIVE_FORMAT=tar.bz2 python3 make_distrib.py --output-dir="$dist" --ninja-build \
        --arm64-build --minimal --no-docs --no-symbols --allow-partial --quiet >&2
    if [[ ! -f "$archive" ]]; then
        echo "make_distrib did not write $archive" >&2
        ls "$dist" >&2
        exit 1
    fi
    echo "$archive"
}

case "${1:-}" in
    checkout) checkout ;;
    build) build "${2:-}" ;;
    package) package ;;
    *) echo "Usage: $0 checkout | build [SECONDS] | package" >&2; exit 2 ;;
esac
