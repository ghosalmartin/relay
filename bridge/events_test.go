package main

import (
	"encoding/json"
	"errors"
	"testing"

	"google.golang.org/protobuf/proto"

	"go.mau.fi/mautrix-gmessages/pkg/libgm"
	"go.mau.fi/mautrix-gmessages/pkg/libgm/events"
	"go.mau.fi/mautrix-gmessages/pkg/libgm/gmproto"
)

func TestTranslateEvent_ClientReadySendsEachConversationThenSyncDone(t *testing.T) {
	ready := &events.ClientReady{Conversations: []*gmproto.Conversation{
		{ConversationID: "a"}, {ConversationID: "b"},
	}}

	got := TranslateEvent(ready)

	assertKinds(t, got, EventConversation, EventConversation, EventInitialSyncDone)
	assertConversationID(t, got[0], "a")
	assertConversationID(t, got[1], "b")
}

func TestTranslateEvent_MessageKindDependsOnWhetherItIsHistorical(t *testing.T) {
	message := &gmproto.Message{MessageID: "m1"}

	live := TranslateEvent(&libgm.WrappedMessage{Message: message})
	old := TranslateEvent(&libgm.WrappedMessage{Message: message, IsOld: true})

	assertKinds(t, live, EventMessage)
	assertKinds(t, old, EventHistoricalMessage)
}

func TestTranslateEvent_PairingCarriesPhoneID(t *testing.T) {
	got := TranslateEvent(&events.PairSuccessful{PhoneID: "phone-1"})

	assertKinds(t, got, EventPaired)
	var payload map[string]string
	if err := json.Unmarshal(got[0].Payload, &payload); err != nil || payload["phone_id"] != "phone-1" {
		t.Fatalf("payload = %s, want phone_id phone-1", got[0].Payload)
	}
}

func TestTranslateEvent_FatalErrorCarriesReason(t *testing.T) {
	got := TranslateEvent(&events.ListenFatalError{Error: errors.New("boom")})

	assertKinds(t, got, EventFatalError)
	if string(got[0].Payload) != "boom" {
		t.Fatalf("payload = %q, want boom", got[0].Payload)
	}
}

func TestTranslateEvent_LogoutSignals(t *testing.T) {
	assertKinds(t, TranslateEvent(&events.GaiaLoggedOut{}), EventLoggedOut)
	assertKinds(t, TranslateEvent(&gmproto.RevokePairData{}), EventLoggedOut)
}

func TestTranslateEvent_PhoneReachability(t *testing.T) {
	assertKinds(t, TranslateEvent(&events.PhoneNotResponding{}), EventPhoneUnreachable)
	assertKinds(t, TranslateEvent(&events.PhoneRespondingAgain{}), EventPhoneReachable)
}

func TestTranslateEvent_IgnoresEventsTheAppDoesNotUse(t *testing.T) {
	if got := TranslateEvent(&events.NoDataReceived{}); len(got) != 0 {
		t.Fatalf("got %d events, want none", len(got))
	}
}

func TestIsSessionChange(t *testing.T) {
	cases := map[string]struct {
		event any
		want  bool
	}{
		"token refresh": {&events.AuthTokenRefreshed{}, true},
		"pairing":       {&events.PairSuccessful{}, true},
		"message":       {&libgm.WrappedMessage{}, false},
	}
	for name, c := range cases {
		if got := IsSessionChange(c.event); got != c.want {
			t.Errorf("%s: IsSessionChange = %v, want %v", name, got, c.want)
		}
	}
}

func assertKinds(t *testing.T, got []Event, want ...EventKind) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("got %d events, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i].Kind != want[i] {
			t.Fatalf("event %d kind = %d, want %d", i, got[i].Kind, want[i])
		}
	}
}

func assertConversationID(t *testing.T, e Event, want string) {
	t.Helper()
	var c gmproto.Conversation
	if err := proto.Unmarshal(e.Payload, &c); err != nil {
		t.Fatalf("decode conversation: %v", err)
	}
	if c.ConversationID != want {
		t.Fatalf("conversation id = %q, want %q", c.ConversationID, want)
	}
}
