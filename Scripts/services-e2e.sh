#!/bin/bash
# End-to-end test of the macOS Services pipeline: launches the built app with
# a deterministic fake engine and invokes the Proofread service for real.
# Usage: Scripts/services-e2e.sh [path-to-bulletproof.app]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-}"
if [[ -z "$APP" ]]; then
  BUILT=$(xcodebuild -project bulletproof.xcodeproj -scheme bulletproof -configuration Debug \
    -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
    | awk '/ BUILT_PRODUCTS_DIR =/{print $3; exit}')
  APP="$BUILT/bulletproof.app"
fi
[[ -d "$APP" ]] || { echo "app not found at $APP - build first"; exit 1; }

# Register the bundle's NSServices with LaunchServices, then launch with the
# fake engine so results are deterministic (CI has no Apple Intelligence).
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
BULLETPROOF_FAKE_ENGINE=1 "$APP/Contents/MacOS/bulletproof" &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
swift Scripts/InvokeService.swift
