# Relay

> [!WARNING]
> **This is a vibecoded app.** It is a personal pet project, written almost entirely by an AI
> coding agent (Claude Code) from prompts, and it has not been reviewed line by line by a human.
> Expect bugs. It handles your private messages, and pairing means signing in to your Google account
> inside the app: the resulting cookies, which give access to that account, are stored in your
> Keychain. A second copy of that login, for the hidden website described under Known limits, is
> stored by WebKit in the app's own folder, without the Keychain's protection. Read the code before you trust it with anything that matters. No support, no warranty,
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
- **Written but not confirmed on a real phone:** starting a new conversation, sending reactions
  and replies, deleting messages, archiving, deleting and muting conversations, playing video and
  audio in a chat, group photos, shared locations, contact photos in the inbox, replying from or
  clicking a notification, notifications with the window closed, and reconnecting automatically
  when the phone stops answering.
- **Not proven yet:** how long a login lasts. Earlier builds lost theirs within 30 minutes, and the
  fix has only been tested for about an hour.

Known limits:

- Your phone has to be on and online with Google Messages running. If the app is swiped away or
  Android pauses it, new messages may still arrive but chats can stop loading until you open it.
- Only one Google Messages client seems to be active at a time, so keep the website closed while
  using Relay. Relay's own hidden copy, below, closes as soon as the phone answers.
- Muting tells the phone, but libgm can't report which chats are muted, so Relay offers both Mute
  and Unmute and your Mac still shows alerts for a muted chat.
- Relay doesn't appear under Device pairing on the phone. Neither did the Google Messages website
  when we checked, so unpair from inside Relay.
- Your phone can stop answering Relay while still delivering new messages. A send it hasn't answered
  within about a minute shows as waiting, because it can still go out minutes later. Sending it again
  may send it twice. Loading the Google Messages website has got the phone answering again each time
  we've tried it in a browser, so Relay asks you to sign in and pair the site once, then loads it out
  of sight as soon as a chat or send goes unanswered for 5 seconds. That has worked from a hidden page
  once so far.

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

## Build it yourself

You need macOS 15 or later, Xcode (last built with 27.2, and opened once so its licence is accepted),
Homebrew, and an Android phone running Google Messages.

**1. Get the code and the tools.**

```sh
git clone https://github.com/ghosalmartin/relay.git
cd relay
brew install xcodegen go
```

**2. Build the Go bridge.** This compiles libgm for both Mac architectures and takes a few minutes.

```sh
./LibGMKit/Bridge/build-xcframework.sh
```

**3. Optional: sign it with your own Apple team.** Without this the app still builds and runs, but
macOS asks about the Keychain on every launch. A free Apple account is enough.

```sh
cp app/Config/Signing.local.xcconfig.example app/Config/Signing.local.xcconfig
```

Then put your team ID in that file, which git ignores. You'll find the ID in Xcode's Signing settings
or on developer.apple.com under Membership.

**4. Build and install.**

```sh
cd app
xcodegen
xcodebuild build -project Relay.xcodeproj -scheme Relay -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/relay-build
mkdir -p ~/Applications
ditto /tmp/relay-build/Build/Products/Debug/Relay.app ~/Applications/Relay.app
open ~/Applications/Relay.app
```

Or run `open Relay.xcodeproj` instead and run the **Relay** scheme from Xcode. Use the Debug
configuration either way: a Release build currently crashes the Swift compiler.

To update later, run `git pull`, repeat step 2 and then step 4, after quitting Relay.

### First launch

Google has discontinued QR code pairing, so you sign in with the Google account on your Android
phone instead. Unlock the phone and open Device pairing in Messages first, because it only has 20
seconds to answer. Then sign in with your password and 2FA on the page Relay shows, and tap the
matching emoji on the phone. If that sign-in doesn't suit your account, Relay can open Chrome (where
passkeys work) so you can copy one request from DevTools as cURL and paste it back in.

Relay then asks you to sign in and pair the Google Messages website too, which is one more sign-in
and emoji. It uses that page, out of sight, to wake your phone when it stops answering. Press **Done**
once you can see your chats, or **Not Now** to skip it and be asked again next launch.

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
