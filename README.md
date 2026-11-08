# Relay

> [!WARNING]
> **This is a vibecoded app.** It is a personal pet project, written almost entirely by an AI
> coding agent (Claude Code) from prompts, and it has not been reviewed line by line by a human.
> Expect bugs. It handles your private messages, and pairing means signing in to your Google account
> inside the app: the resulting cookies, which give access to that account, are stored in your
> Keychain. Read the code before you trust it with anything that matters. No support, no warranty,
> no promises.

A native macOS client for Google Messages (Android Messages), written in SwiftUI on
top of [libgm](https://github.com/mautrix/gmessages/tree/main/pkg/libgm).
Working name. Not affiliated with or endorsed by Google.

macOS only. It needs an Android phone running Google Messages: your texts live on the phone,
and the Mac pairs with it the same way messages.google.com/web does. libgm uses an unofficial
protocol, so Google could break this at any time.

Licensed AGPL-3.0, because libgm is (see LICENSE).

## Status

Early and unfinished. There are no releases yet, so you have to build it yourself.

- Package tests and UI tests pass, but the UI tests run against a scripted client.
- **It has not been tried with a real phone yet**, so pairing, real messages and real
  notifications are all unproven.
- Written so far: Google account pairing, inbox, threads, sending text, and macOS notifications that open
  their conversation when clicked.

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
    UserNotificationsAdapter/  NotificationPresenter on macOS Notification Centre.
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
brew install xcodegen go
./LibGMKit/Bridge/build-xcframework.sh
cd app && xcodegen && open Relay.xcodeproj
```

Run the **Relay** scheme. Google has discontinued QR code pairing, so you sign in with the Google
account on your Android phone instead: Relay opens Chrome (where passkeys work), you copy one
request from DevTools as cURL and paste it back into Relay, then tap the matching emoji in
Messages on the phone.

## Tests

```sh
cd LibGMKit/Bridge && go test -race ./...          # Go bridge
cd LibGMKit && swift test                           # binding, incl. the real bridge
cd app && swift test                                # domain, use cases, view models, adapters
xcodebuild test -project app/Relay.xcodeproj -scheme Relay   # UI flows (macOS)
```

## Updating libgm

```sh
cd LibGMKit/Bridge && go get go.mau.fi/mautrix-gmessages@main && go mod tidy
cd .. && ./scripts/gen-protos.sh         # needs protoc + protoc-gen-swift
./Bridge/build-xcframework.sh
```

Generated protobuf sources are committed, so a normal build needs neither protoc nor
a protobuf toolchain. Regenerate whenever libgm or swift-protobuf changes version.
