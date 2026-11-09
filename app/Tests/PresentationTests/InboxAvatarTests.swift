import Foundation
import MessagingApplication
import MessagingDomain
import MessagingTestSupport
@testable import Presentation
import Testing

private let sam = ParticipantID("sam")
private let photo = Data("photo".utf8)

private func chat(_ id: String, with person: ParticipantID = sam, isGroup: Bool = false) -> Conversation {
    Conversation(
        id: ConversationID(id), title: "Sam", preview: nil, lastActivity: Date(timeIntervalSince1970: 0),
        isUnread: false, isGroup: isGroup,
        participants: [
            Participant(id: ParticipantID("me"), displayName: "Me", phoneNumber: nil, isMe: true),
            Participant(id: person, displayName: "Sam", phoneNumber: nil, isMe: false),
        ]
    )
}

@Suite struct InboxAvatarStateTests {
    @Test func theOtherPersonsPhotoIsWantedOnceSyncHasFinished() {
        #expect(InboxState(conversations: [chat("c1")], isSyncing: false).avatarsToLoad == [sam])
        #expect(InboxState(conversations: [chat("c1")], isSyncing: true).avatarsToLoad.isEmpty)
    }

    @Test func aGroupShowsUpToTwoOfItsMembers() {
        let members = ["a", "b", "c"].map { Participant(id: ParticipantID($0), displayName: $0, phoneNumber: nil, isMe: false) }
        let me = Participant(id: ParticipantID("me"), displayName: "Me", phoneNumber: nil, isMe: true)
        let group = Conversation(id: ConversationID("g"), title: "Group", preview: nil, lastActivity: Date(), isUnread: false, isGroup: true, participants: [me] + members)
        let state = InboxState(
            conversations: [group],
            isSyncing: false,
            avatars: [ParticipantID("a"): Data("a".utf8), ParticipantID("b"): Data("b".utf8)],
            requestedAvatars: [ParticipantID("a"), ParticipantID("b")]
        )

        #expect(state.avatarsToLoad.isEmpty)
        #expect(state.rows[0].avatar == Data("a".utf8))
        #expect(state.rows[0].secondAvatar == Data("b".utf8))
        #expect(group.avatarParticipants == [ParticipantID("a"), ParticipantID("b")])
    }

    @Test func theShortcutsFollowTheListAsShown() {
        let state = InboxState(conversations: [chat("c1"), chat("c2")])

        #expect(state.conversationID(atShortcut: 2) == ConversationID("c2"))
        #expect(state.conversationID(atShortcut: 3) == nil)
    }

    @Test func nobodyIsAskedForTwice() {
        let state = InboxReducer.reduce(
            InboxState(conversations: [chat("c1")], isSyncing: false),
            .avatarsRequested([sam])
        )

        #expect(state.avatarsToLoad.isEmpty)
    }

    @Test func aFailedRequestCanBeTriedAgain() {
        let state = InboxReducer.reduce(
            InboxState(conversations: [chat("c1")], isSyncing: false, requestedAvatars: [sam]),
            .avatarsFailed([sam])
        )

        #expect(state.avatarsToLoad == [sam])
    }

    @Test func aLoadedPhotoReachesTheRow() {
        let state = InboxReducer.reduce(InboxState(conversations: [chat("c1")]), .avatarsLoaded([sam: photo]))

        #expect(state.rows.first?.avatar == photo)
    }

    @Test func anEmptiedInboxForgetsThePhotos() {
        let state = InboxReducer.reduce(
            InboxState(conversations: [chat("c1")], avatars: [sam: photo], requestedAvatars: [sam]),
            .inboxChanged(InboxSnapshot(conversations: [], isSyncing: true))
        )

        #expect(state.avatars.isEmpty)
        #expect(state.requestedAvatars.isEmpty)
    }
}

@MainActor
@Suite struct InboxAvatarLoadingTests {
    @Test func photosLoadInOneRequestAfterTheSync() async {
        let client = FakeMessagingClient()
        let ben = ParticipantID("ben")
        client.stubAvatars(.success([sam: photo]))
        let session = LiveSession(client: client)
        let pump = Task { await session.run() }
        let viewModel = InboxViewModel(
            observeInbox: ObserveInbox(session: session),
            observeConnectionStatus: ObserveConnectionStatus(session: session),
            focus: ConversationFocus(),
            loadAvatars: LoadAvatars(client: client),
            archive: ArchiveConversation(client: client),
            delete: DeleteConversation(client: client),
            mute: MuteConversation(client: client)
        )
        let running = Task { await viewModel.run() }

        client.emit(.conversationUpdated(chat("c1")))
        client.emit(.conversationUpdated(chat("c2", with: ben)))
        client.emit(.initialSyncCompleted)

        #expect(await eventually { viewModel.state.avatars[sam] == photo })
        #expect(client.calls.filter { if case .avatars = $0 { true } else { false } } == [.avatars([sam, ben])])
        running.cancel()
        pump.cancel()
    }
}
