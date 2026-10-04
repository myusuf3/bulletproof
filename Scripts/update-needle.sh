#!/usr/bin/env bash
# Vendors Cactus's prebuilt speech engine (libneedle.a + needle.h, Apache-2.0)
# from Hugging Face into Packages/Needle as a static-library xcframework.
# Pinned to a repo revision so every build links the same engine; bump
# NEEDLE_REVISION to update, then rebuild and run the dictation tests.
set -euo pipefail

NEEDLE_REVISION="${NEEDLE_REVISION:-c7c415a3d1b3d929014bc6e866d51ebb971f7089}"
BASE="https://huggingface.co/Cactus-Compute/needle3/resolve/${NEEDLE_REVISION}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/Packages/Needle"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/include"
curl -fsSL "$BASE/macos-arm64/libneedle.a" -o "$WORK/libneedle.a"
curl -fsSL "$BASE/macos-arm64/needle.h" -o "$WORK/include/needle.h"
curl -fsSL "$BASE/LICENSE" -o "$WORK/LICENSE"
cat > "$WORK/include/module.modulemap" <<'EOF'
module CNeedle {
    header "needle.h"
    export *
}
EOF

rm -rf "$PACKAGE/CNeedle.xcframework"
xcodebuild -create-xcframework \
    -library "$WORK/libneedle.a" -headers "$WORK/include" \
    -output "$PACKAGE/CNeedle.xcframework" >/dev/null
cp "$WORK/LICENSE" "$PACKAGE/LICENSE-needle"
echo "Vendored needle3@${NEEDLE_REVISION} into $PACKAGE"
