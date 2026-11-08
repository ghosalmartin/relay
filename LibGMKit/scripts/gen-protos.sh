#!/usr/bin/env bash
# Generates Swift types from libgm's .proto files, at the exact libgm version pinned
# in Bridge/go.mod, so Go and Swift always agree on the wire format.
# Needs protoc and protoc-gen-swift on PATH (brew install protobuf swift-protobuf).
set -euo pipefail
cd "$(dirname "$0")/.."
PROTO_DIR="$(cd Bridge && go list -m -f '{{.Dir}}' go.mau.fi/mautrix-gmessages)/pkg/libgm/gmproto"
OUT=Sources/LibGMKit/Generated
mkdir -p "$OUT" && rm -f "$OUT"/*.pb.swift
"${PROTOC:-protoc}" -I "$PROTO_DIR" \
  --swift_out="$OUT" --swift_opt=Visibility=Public \
  "$PROTO_DIR"/*.proto "$PROTO_DIR"/vendor/*.proto
echo "Generated $(find "$OUT" -name "*.pb.swift" | wc -l | tr -d ' ') files into $OUT"
