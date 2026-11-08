# Relay

A native macOS client for Google Messages (Android Messages), written in SwiftUI on
top of [libgm](https://github.com/mautrix/gmessages/tree/main/pkg/libgm).
Working name. Not affiliated with Google.

Licensed AGPL-3.0, because libgm is (see LICENSE).

## Layout

```
LibGMKit/                 Standalone Swift binding for libgm (could be its own repo)
  Bridge/                   Go → C bridge over libgm, built as a static library
  Sources/LibGMKit/         LibGMSession, events, generated protobuf types
app/                      The Relay app
  Sources/
    MessagingDomain/        Entities and ports (MessagingClient, SessionStore). No dependencies.
    MessagingApplication/   Use cases, one per file. Depends on the domain only.
    Presentation/           MVI view models + pure reducers. No SwiftUI.
    LibGMAdapter/           The only code that knows libgm exists: LibGMKit → MessagingClient.
    KeychainAdapter/        SessionStore in the Keychain.
    AsyncBroadcast/         One stream, many subscribers (Swift's missing SharedFlow).
  RelayApp/                 SwiftUI views + composition root (AppEnvironment)
  RelayUITests/             XCUITest flows against a scripted client
  Tests/                    Unit tests for every package target
```

Dependencies point inwards and the compiler enforces it: each layer is its own
SwiftPM target, so the domain cannot import libgm even by accident. To replace libgm,
write another `MessagingClient` and change one line in `AppEnvironment`.

## How a screen works (MVI)

```
View ──Intent──▶ ViewModel ──calls──▶ Use case ──▶ MessagingClient (port)
  ▲                   │                                  │
  └──── State ◀── Reducer ◀──────── Mutation ◀───────────┘
```

Views render `state` and call `send(intent)`, nothing else. Reducers are pure
functions, so every display rule is a plain unit test.

## Build and run (macOS 15+, Xcode 16+, Go 1.26+)

```sh
brew install xcodegen
./LibGMKit/Bridge/build-xcframework.sh
cd app && xcodegen && open Relay.xcodeproj
```

Run the **Relay** scheme and scan the QR code with Messages on your phone
(profile picture → Device pairing → QR code scanner).

## Tests

```sh
cd LibGMKit/Bridge && go test -race ./...          # Go bridge
cd LibGMKit && swift test                           # binding, incl. the real bridge
cd app && swift test                                # domain, use cases, view models, adapters
xcodebuild test -project app/Relay.xcodeproj -scheme Relay   # UI flows (macOS)
```

Everything except SwiftUI and the Keychain also builds and tests on Linux
(`./LibGMKit/Bridge/build-linux.sh` first), which is what CI's Linux job does.

## Updating libgm

```sh
cd LibGMKit/Bridge && go get go.mau.fi/mautrix-gmessages@main && go mod tidy
cd .. && ./scripts/gen-protos.sh         # needs protoc + protoc-gen-swift
./Bridge/build-xcframework.sh
```

Generated protobuf sources are committed, so a normal build needs neither protoc nor
a protobuf toolchain. Regenerate whenever libgm or swift-protobuf changes version.
