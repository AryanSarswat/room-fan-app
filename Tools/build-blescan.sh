#!/bin/bash
# Builds the Bluetooth probe with the usage description macOS requires.
# Run the result from Terminal.app so the permission prompt can appear.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product blescan \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker Tools/blescan-Info.plist
echo "Built .build/release/blescan — run it from Terminal.app:"
echo "  ./.build/release/blescan 20"
