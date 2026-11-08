# Relay

A native SwiftUI macOS client for Google Messages (Android Messages), built on
[libgm](https://github.com/mautrix/gmessages/tree/main/pkg/libgm) from mautrix-gmessages.
Working name; not affiliated with Google.

Licensed AGPL-3.0, because libgm is. See LICENSE.

## Layout

```
bridge/   Go → C bridge over libgm (static lib → GMBridge.xcframework)
app/      SwiftUI app + RelayKit (Swift wrapper over the bridge)
scripts/  proto generation
```

## Build (macOS 14+, Xcode 16+, Go 1.26+)

```sh
brew install protobuf swift-protobuf xcodegen
./bridge/build-xcframework.sh     # Go → GMBridge.xcframework
./scripts/gen-protos.sh           # libgm .proto → Swift types
cd app && xcodegen && open Relay.xcodeproj
```

Run the Relay scheme, scan the QR with Messages on your phone
(profile picture → Device pairing → QR code scanner).

## How it fits together

- `bridge/bridge.go` exports a small C ABI: `gm_session_new`, pairing, `gm_connect`,
  and one generic `gm_call(method, protobuf bytes)` for every RPC.
- Events come back on one C callback as `(kind, bytes)`. Bytes are libgm's own
  protobuf messages, decoded in Swift with types generated from the same .proto
  files at the same pinned version, so the two sides can't drift.
- `GMSession` (RelayKit) turns that into `async throws` calls and an
  `AsyncStream<GMEvent>`.
- The session blob is stored in the Keychain so the app reconnects without re-pairing.

## Updating libgm

```sh
cd bridge && go get go.mau.fi/mautrix-gmessages@main && go mod tidy
cd .. && ./scripts/gen-protos.sh && ./bridge/build-xcframework.sh
```

Linux smoke test of the C ABI (no network):

```sh
cd bridge && go build -buildmode=c-archive -o build/libgmbridge.a . \
  && cc smoketest/main.c build/libgmbridge.a -lpthread -lresolv -o build/smoke && ./build/smoke
```
