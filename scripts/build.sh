#!/bin/bash
# Builds Flux.app into build/DerivedData. Pass "release" for a release build, and --run to launch it.
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

"$ROOT/scripts/fetch-cef.sh"
cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project Flux.xcodeproj -scheme Flux -configuration "$CONFIGURATION" \
    -derivedDataPath build/DerivedData -quiet build

APP="$ROOT/build/DerivedData/Build/Products/$CONFIGURATION/Flux.app"
echo "Built $APP"
if $RUN; then
    open "$APP"
fi
