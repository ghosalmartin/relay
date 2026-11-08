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
- **Tested with one real Android phone:** Google account pairing, the inbox and threads, receiving
  pictures and audio, sending text and pictures, macOS notifications, and reconnecting after a
  restart without pairing again.
- **Written but not confirmed on a real phone:** reactions, replies, shared locations, contact
  photos in the inbox, clicking a notification to open its conversation, notifications with the
  window closed, and reconnecting automatically when the phone stops answering.
- **Not proven yet:** how long a login lasts. Earlier builds lost theirs within 30 minutes, and the
  fix has only been tested for about an hour.

Known limits:

- Your phone has to be on and online with Google Messages running. If the app is swiped away or
  Android pauses it, new messages may still arrive but chats can stop loading until you open it.
- Only one Google Messages client seems to be active at a time, so keep the website closed while
  using Relay.
- Relay doesn't appear under Device pairing on the phone. Neither did the Google Messages website
  when we checked, so unpair from inside Relay.
- A message fails if the phone doesn't answer within about a minute. Beeper, which uses the same
  library, [holds messages until the phone is back](https://help.beeper.com/chat-networks/google-messages-getting-started-guide).
  Relay should do that too, and show that a message is waiting for your phone.

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
account on your Android phone instead. Unlock the phone and open Device pairing in Messages first,
because it only has 20 seconds to answer. Then choose **Sign in here instead** and use your
password and 2FA, and tap the matching emoji on the phone. If that sign-in doesn't suit your
account, Relay can open Chrome (where passkeys work) so you can copy one request from DevTools as
cURL and paste it back in.

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

## Thanks

Huge thanks to everyone behind [mautrix-gmessages](https://github.com/mautrix/gmessages) and
libgm. They did the hard work of figuring out how Google Messages talks to the phone, and Relay
would not exist without it.
