#!/bin/bash
# Builds Flux.app. Pass "release" for a release build, and --run to launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="Debug"
RUN=false
for ARG in "$@"; do
    case "$ARG" in
        release) CONFIGURATION="Release" ;;
        --run) RUN=true ;;
        *) echo "Unknown argument: $ARG" >&2; exit 1 ;;
    esac
done

# Outside the source folder: when it sits in ~/Documents, macOS asks for access to Documents on
# every launch, because the app reads its own bundle from there. FLUX_DERIVED_DATA keeps the build
# of another branch apart from the Flux in daily use.
DERIVED_DATA="${FLUX_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Flux}"

"$ROOT/scripts/fetch-engine.sh"
cd "$ROOT"
xcodegen generate --quiet
# An ad hoc signature changes with every build, and macOS then asks again for the keychain items
# Flux saved. A development certificate, when there is one, keeps the same signature.
SIGNING=()
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development/ { print $2; exit }')"
if [ -n "$IDENTITY" ]; then
    # Swift packages' resource bundles want the certificate's team too.
    TEAM="$(security find-certificate -Z -a -p -c "Apple Development" 2>/dev/null \
        | awk -v hash="$IDENTITY" '/^SHA-1 hash:/ { found = ($3 == hash) } found && /BEGIN CERTIFICATE/,/END CERTIFICATE/' \
        | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')"
    SIGNING=(CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM="$TEAM")
fi

xcodebuild -project Flux.xcodeproj -scheme Flux -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" -quiet build ${SIGNING[@]+"${SIGNING[@]}"}

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Flux.app"
echo "Built $APP"
if $RUN; then
    open "$APP"
fi
