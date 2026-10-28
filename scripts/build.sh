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
# every launch, because the app reads its own bundle from there.
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Flux"

"$ROOT/scripts/fetch-cef.sh"
cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project Flux.xcodeproj -scheme Flux -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" -quiet build

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Flux.app"
echo "Built $APP"
if $RUN; then
    open "$APP"
fi
