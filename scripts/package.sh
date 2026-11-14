#!/bin/bash
# Builds Flux in release, signs it and puts it in build/Flux.dmg.
#
# FLUX_SIGNING_IDENTITY is the SHA-1 hash or the name of the certificate to sign with, and
# FLUX_KEYCHAIN the keychain it is in, when it isn't the login one. Without an identity the app
# keeps an ad hoc signature, which is only good for trying the package out.
#
# FLUX_SPARKLE_KEY is the private EdDSA key Sparkle checks updates with. With it, the script writes
# the DMG's signature and length to build/Flux.dmg.sparkle, which the update feed reads.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export FLUX_DERIVED_DATA="${FLUX_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/FluxRelease}"
APP="$FLUX_DERIVED_DATA/Build/Products/Release/Flux.app"
DMG="$ROOT/build/Flux.dmg"

"$ROOT/scripts/build.sh" release

if [ -n "${FLUX_SIGNING_IDENTITY:-}" ]; then
    # --deep reaches the engine's helper apps, which Xcode signed ad hoc when embedding them.
    codesign --force --deep --sign "$FLUX_SIGNING_IDENTITY" \
        ${FLUX_KEYCHAIN:+--keychain "$FLUX_KEYCHAIN"} "$APP"
    codesign --verify --deep --strict "$APP"
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$ROOT/build"
rm -f "$DMG"
hdiutil create -quiet -volname Flux -srcfolder "$STAGING" -format UDZO "$DMG"

if [ -n "${FLUX_SPARKLE_KEY:-}" ]; then
    SIGN_UPDATE="$FLUX_DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
    printf %s "$FLUX_SPARKLE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$DMG" > "$DMG.sparkle"
fi
echo "Packaged $DMG"
