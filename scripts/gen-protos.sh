#!/usr/bin/env bash
# Generates Swift types (Gmproto_*) from libgm's .proto files, at the exact
# libgm version pinned in bridge/go.mod so Go and Swift always agree on the wire.
# Needs: brew install protobuf swift-protobuf
set -euo pipefail
cd "$(dirname "$0")/.."
LIBGM_DIR="$(cd bridge && go list -m -f '{{.Dir}}' go.mau.fi/mautrix-gmessages)/pkg/libgm/gmproto"
OUT=app/Sources/RelayKit/Generated
mkdir -p "$OUT" && rm -f "$OUT"/*.pb.swift
protoc -I "$LIBGM_DIR" -I "$LIBGM_DIR/vendor" \
  --swift_out="$OUT" --swift_opt=Visibility=Public \
  "$LIBGM_DIR"/*.proto
echo "Generated $(ls "$OUT" | wc -l | tr -d ' ') files into $OUT"
