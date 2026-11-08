#!/usr/bin/env bash
# Builds GMBridge.xcframework (macOS arm64 + x86_64) from the Go bridge.
# Run on a Mac with Go 1.26+ and Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

MIN_MACOS="${MIN_MACOS:-14.0}"
OUT=build
rm -rf "$OUT/darwin-"* "$OUT/GMBridge.xcframework"

build_arch() {
  local goarch=$1 clangarch=$2
  local dir="$OUT/darwin-$goarch"
  mkdir -p "$dir"
  CGO_ENABLED=1 GOOS=darwin GOARCH="$goarch" \
  CC="$(xcrun -f clang)" \
  CGO_CFLAGS="-arch $clangarch -mmacosx-version-min=$MIN_MACOS -isysroot $(xcrun --sdk macosx --show-sdk-path)" \
  CGO_LDFLAGS="-arch $clangarch -mmacosx-version-min=$MIN_MACOS" \
    go build -trimpath -buildmode=c-archive -o "$dir/libgmbridge.a" .
}

build_arch arm64 arm64
build_arch amd64 x86_64

mkdir -p "$OUT/universal/include"
lipo -create "$OUT/darwin-arm64/libgmbridge.a" "$OUT/darwin-amd64/libgmbridge.a" \
  -output "$OUT/universal/libgmbridge.a"
cp "$OUT/darwin-arm64/libgmbridge.h" "$OUT/universal/include/libgmbridge.h"
cat > "$OUT/universal/include/module.modulemap" <<'EOF'
module GMBridgeC {
    header "libgmbridge.h"
    link "resolv"
    export *
}
EOF

xcodebuild -create-xcframework \
  -library "$OUT/universal/libgmbridge.a" -headers "$OUT/universal/include" \
  -output "$OUT/GMBridge.xcframework"

echo "Built $OUT/GMBridge.xcframework"
