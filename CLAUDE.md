# Relay

Native SwiftUI macOS client for Google Messages, built on libgm (Go, from mautrix-gmessages).
Free and open source under AGPL-3.0. Working name; never call it "Google Messages" or use Google's icon.

## Architecture rules (non-negotiable)

Ports and adapters. Each layer is its own SwiftPM target, and dependencies point inwards only:

- `MessagingDomain`: entities and ports (`MessagingClient`, `SessionStore`). Imports nothing but Foundation.
- `MessagingApplication`: use cases, one per file, as structs with `callAsFunction`. Depends on the domain only.
- `Presentation`: MVI view models and pure reducers. No SwiftUI imports.
- `LibGMAdapter`: the ONLY code that may import LibGMKit. Maps libgm protobufs to domain types.
- `KeychainAdapter`: implements `SessionStore`.
- `RelayApp/`: SwiftUI views plus `AppEnvironment`, the single composition root.
- `LibGMKit/`: standalone package (Go bridge, generated protos, `LibGMSession`). Knows nothing about Relay.

Never let libgm or protobuf types leak above `LibGMAdapter`.

## MVI, for every screen

`State` (struct), `Intent` (what the user did), `Mutation` (what happened), `Reducer.reduce(state, mutation)`
(pure, no async/IO/clock), and a `@MainActor @Observable` view model exposing `state`, `send(_:)` and
`run()` (long-running, called from `.task`).

Views render `state` and call `send(...)`. No logic, formatting rules or async calls in views:
display rules belong in state or reducer code where they can be unit tested.

## Code style

- Swift 6 language mode, strict concurrency. async/await and structured concurrency. No Combine.
- `AsyncSequence` for streams. `AsyncStream` is single-consumer; fan out with `AsyncBroadcast.Broadcaster`.
- Typed throws where a layer has its own error type (`MessagingError`, `LibGMError`).
- Clean Code: small types, one type per file (feature contracts may group State/Intent/Mutation),
  names that say what things do, comments that explain why, not what.
- Native macOS look: system controls, accent colour, SF Symbols, light and dark mode. No copied branding.

## Tests

Every behaviour change comes with tests. Use `MessagingTestSupport` (`FakeMessagingClient`,
`InMemorySessionStore`, `ManualClock`, `Fixtures`, `eventually`). Never use real sleeps or timing in tests.

```sh
cd LibGMKit/Bridge && go vet ./... && go test -race ./...
cd LibGMKit && swift test
cd app && swift test
cd app && xcodegen && xcodebuild test -project Relay.xcodeproj -scheme Relay -destination 'platform=macOS'
```

UI tests launch the app with `--ui-testing`, which makes `AppEnvironment` use a scripted
`FakeMessagingClient` (see `RelayApp/Composition/UITestLaunch.swift`), so they need no phone.

## Build

```sh
brew install xcodegen go
./LibGMKit/Bridge/build-xcframework.sh   # Go -> GMBridge.xcframework (rerun after Go changes)
cd app && xcodegen && open Relay.xcodeproj
```

## Status

M0 (foundations) is done: Go, LibGMKit and app package tests pass on Linux.
The SwiftUI views, KeychainAdapter and UI tests were written without a Mac compiler,
so they have never been built. M1 starts by building on macOS, fixing compile errors,
getting the UI tests green, then pairing a real phone.

## Bridge ABI

Event kinds (`Bridge/events.go` ↔ `BridgeEventKind.swift`) and method IDs (`Bridge/rpc.go` ↔
`BridgeMethod.swift`) are numbered constants shared across the boundary. Never renumber them;
only append new ones.
