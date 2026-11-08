#!/usr/bin/env bash
# Builds the bridge as a static library for Linux, so LibGMKit builds and tests on
# Linux CI as well as macOS. Output: build/linux/{libgmbridge.a, libgmbridge.h, module.modulemap}
set -euo pipefail
cd "$(dirname "$0")"
OUT=build/linux
mkdir -p "$OUT"
CGO_ENABLED=1 go build -trimpath -buildmode=c-archive -o "$OUT/libgmbridge.a" .
cat > "$OUT/module.modulemap" <<'MAP'
module GMBridgeC {
    header "libgmbridge.h"
    link "gmbridge"
    link "resolv"
    export *
}
MAP
echo "Built $OUT"
