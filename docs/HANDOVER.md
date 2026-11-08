# Handover: M0 → M1

Written at the end of the first build session (8 Nov 2026), which ran in a Linux sandbox with no Mac.
Read CLAUDE.md first for the standing rules; this file is the session context: what exists, what
was decided and why, what is unverified, and what to do next.

## Where things stand

| Area | State | Verified how |
| --- | --- | --- |
| Go bridge (`LibGMKit/Bridge`) | Done | 17 Go tests under `-race`, C smoke test |
| LibGMKit Swift package | Done | 15 tests on Linux, incl. calls through the real Go library |
| Domain, use cases, AsyncBroadcast | Done | Unit tests on Linux |
| Presentation (MVI view models, reducers) | Done | Unit tests on Linux |
| LibGMAdapter | Done | Mapper and client tests with a fake session, on Linux |
| KeychainAdapter | Written | **Never compiled** (Security framework is Apple-only) |
| SwiftUI views, `AppEnvironment`, `UITestLaunch` | Written | **Never compiled** |
| UI tests (`RelayUITests`) | Written | **Never run** |
| `project.yml` (XcodeGen) | Written | **Never generated** |
| `build-xcframework.sh` | Written | **Never run** (needs macOS + Xcode) |
| Pairing with a real phone | Not tried | — |

App package total: 71 tests passing, stable over 10 consecutive runs.

## Do these first, in order

1. **Build the native library.** `./LibGMKit/Bridge/build-xcframework.sh`. Needs Go 1.26+ and Xcode CLT.
2. **Package tests on macOS.** `cd app && swift test`. This also compiles and runs `KeychainAdapter` for the first time.
3. **Generate and build the app.** `cd app && xcodegen && xcodebuild build -project Relay.xcodeproj -scheme Relay`.
   Expect SwiftUI compile errors; the views were written blind. Fix them without moving logic into views.
4. **Fix the inbox subscription race (known bug, below)** before trusting any UI test.
5. **UI tests green.** `xcodebuild test -project Relay.xcodeproj -scheme Relay -destination 'platform=macOS'`.
6. **Pair a real phone** and check the M1 list: inbox fills, a thread loads, send and receive text, unpair.
7. **Push to GitHub** so `.github/workflows/ci.yml` runs (Linux job and macOS job).

## Known bug: inbox can miss the initial conversations

`Broadcaster` does not replay. `InboxViewModel` only subscribes when `InboxView` appears, which is
after `RootViewModel` switches to `.inbox`, which is after `connect()` returns (or after `.paired`).
libgm sends the initial conversations as a burst right after connecting (`ClientReady` →
`.conversationUpdated` × N, then `.initialSyncCompleted`). If that burst lands before the inbox
subscribes, the inbox stays empty and the spinner never stops.

The same race exists in `UITestLaunch`, which emits the demo inbox 300 ms after `.paired`.

Pick one fix and test it with `FakeMessagingClient` (emit before subscribing, then assert):

- **Preferred:** keep the inbox at app scope. Create one `ObserveInbox` projection in `AppEnvironment`
  that starts before `StartSession` runs and holds the latest `InboxSnapshot`. `InboxViewModel` reads
  the current snapshot and then follows changes. This also gives a cache seam for M2.
- Or add a fetch to the port (`func conversations() async throws(MessagingError) -> [Conversation]`,
  backed by `LibGMSession.listConversations`) and have `ObserveInbox` seed from it before following events.

Don't fix it by adding replay to `Broadcaster`. Replaying everything to late subscribers would also
replay pairing codes and messages to screens that shouldn't see them.

## Other things worth checking

- **Thread title can go stale.** `InboxView` builds a `ThreadViewModel` inside `body`; `@State` keeps the first one
  and `.id(conversation.id)` resets it per conversation, but a rename of the same conversation won't
  update the title. Low priority.
- **Fragile error mapping.** `ErrorMapper` recognises "not logged in" and timeouts by matching libgm's error *text*.
  If libgm wording changes, `StartSession` stops clearing dead sessions. A better fix is to have the Go bridge
  return typed error codes alongside the text (new ABI field; append-only).
- **SwiftUI APIs to double-check if they fail to compile:** `.fill.tertiary` in `MessageBubbleView`,
  `.separator` in `ComposerView`, `.relative(presentation:unitsStyle:)` in `ConversationRowView`.
- **Sandbox.** The App Sandbox only has `network.client`. libgm needs outbound HTTPS to Google and nothing else.
  The Keychain works in the sandbox. If pairing hangs, check the console for sandbox denials first.
- **Module path.** The Go module path is `github.com/ghosalmartin/relay/bridge`. Change it if the repo lives elsewhere.

## Decisions made, and why

- **SwiftUI, not Compose Multiplatform.** CMP on the desktop is JVM + Skia: a bundled runtime and no native feel,
  and notifications, Dock, menu bar and Keychain are awkward. Calling Go from the JVM (JNA/Panama, two runtimes,
  signal-handler conflicts) is harder than Swift calling a C library. A future Windows/Linux client can reuse
  the same bridge through JNA, or by running it as a sidecar process.
- **In-process Go library, not a sidecar process.** It's simpler and already working. The protocol (method ID
  plus protobuf bytes) is already shaped so it could move behind a socket unchanged.
- **Protobuf over the C boundary.** Swift types are generated from libgm's own `.proto` files at the pinned
  version, so the two sides can't drift. Generated sources are committed, so a normal build needs no protoc.
- **LibGMKit as its own package.** It's the first Swift binding for libgm and useful to others. It lives in its
  own folder with its own `Package.swift` and gets its own repo after M3, once the API has settled.
- **AGPL-3.0, no Mac App Store.** libgm's licence exceptions cover only Beeper and Element. Distribute as a
  notarised DMG, a Homebrew cask, and Sparkle updates.
- **macOS 15 minimum**, for `Synchronization.Mutex`, which lets `Broadcaster` and the fakes be called from
  synchronous code such as the C callback.
- **Swift Testing**, not XCTest, for unit tests. XCTest only for UI tests.
- **swift-protobuf 1.39.0.** The generator must match the library version. When you bump one, regenerate
  with `LibGMKit/scripts/gen-protos.sh` (`brew install protobuf swift-protobuf`).

## Roadmap after M1

- **M2 Proper app:** local cache (GRDB or SwiftData behind a new port), message search, inline images,
  contact avatars, sending attachments. Gate: opens instantly and reads offline from the cache.
- **M3 Mac-native:** notifications with inline reply, Dock badge, menu bar extra, Spotlight.
  Gate: LibGMKit API unchanged for a month, then it moves to its own repo.
- **M4 Release 1.0:** Developer ID signing, notarised DMG, Sparkle, Homebrew cask, final name.

## Map of the code

```
LibGMKit/Bridge/abi.go          C exports only; convert and delegate
LibGMKit/Bridge/session.go      owns the libgm client
LibGMKit/Bridge/events.go       pure libgm event → bridge event translation
LibGMKit/Bridge/rpc.go          method table against the MessagesAPI interface
LibGMKit/Sources/LibGMKit/      LibGMSession, LibGMEvent, NativeBridge/CBridge, Generated/
app/Sources/MessagingDomain/    entities, MessagingEvent, MessagingError, ports
app/Sources/MessagingApplication/  StartSession, PairDevice, PersistSessionChanges, Unpair,
                                ObserveInbox (+ InboxProjection), LoadThreadHistory, ObserveThread,
                                SendText, MarkConversationRead, ObserveConnectionStatus
app/Sources/Presentation/       Root, Pairing, Inbox, Thread: Contract, Reducer, ViewModel (+ ThreadLayout)
app/Sources/LibGMAdapter/       LibGMMessagingClient, GoogleMessagesSession, Mapping/
app/Sources/KeychainAdapter/    KeychainSessionStore
app/RelayApp/                   SwiftUI views, AppEnvironment, UITestLaunch
app/Tests/MessagingTestSupport/ fakes, fixtures, ManualClock, eventually()
```
