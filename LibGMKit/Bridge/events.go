package main

import (
	"encoding/json"

	"google.golang.org/protobuf/proto"

	"go.mau.fi/mautrix-gmessages/pkg/libgm"
	"go.mau.fi/mautrix-gmessages/pkg/libgm/events"
	"go.mau.fi/mautrix-gmessages/pkg/libgm/gmproto"
)

// EventKind identifies an event crossing the C boundary.
// Values are part of the ABI: keep in sync with BridgeEventKind in Swift, never renumber.
type EventKind int32

const (
	EventQRCode              EventKind = 1  // utf8: QR URL to render
	EventPaired              EventKind = 2  // json: {"phone_id": "..."}
	EventSessionUpdated      EventKind = 3  // json: opaque session blob to persist
	EventInitialSyncDone     EventKind = 4  // empty
	EventConversation        EventKind = 5  // proto: gmproto.Conversation
	EventMessage             EventKind = 6  // proto: gmproto.Message (live)
	EventHistoricalMessage   EventKind = 7  // proto: gmproto.Message (backfill/resync)
	EventTyping              EventKind = 8  // proto: gmproto.TypingData
	EventSettings            EventKind = 9  // proto: gmproto.Settings
	EventPhoneUnreachable    EventKind = 10 // empty
	EventPhoneReachable      EventKind = 11 // empty
	EventFatalError          EventKind = 12 // utf8: reason; session is dead
	EventTransientError      EventKind = 13 // utf8: reason; libgm retries
	EventConnectionRecovered EventKind = 14 // empty
	EventLoggedOut           EventKind = 15 // empty
	EventGoogleAccountEmoji  EventKind = 16 // utf8: emoji to confirm on the phone
)

// Event is one notification for the host app: a kind plus its encoded payload.
type Event struct {
	Kind    EventKind
	Payload []byte
}

// TranslateEvent maps a libgm event to zero or more bridge events.
// Pure: no I/O, no session state, so it is unit-testable in isolation.
func TranslateEvent(evt any) []Event {
	switch e := evt.(type) {
	case *events.ClientReady:
		return translateClientReady(e)
	case *events.PairSuccessful:
		return []Event{jsonEvent(EventPaired, map[string]string{"phone_id": e.PhoneID})}
	case *gmproto.Conversation:
		return protoEvents(EventConversation, e)
	case *libgm.WrappedMessage:
		return protoEvents(messageKind(e), e.Message)
	case *gmproto.TypingData:
		return protoEvents(EventTyping, e)
	case *gmproto.Settings:
		return protoEvents(EventSettings, e)
	case *events.PhoneNotResponding:
		return signal(EventPhoneUnreachable)
	case *events.PhoneRespondingAgain:
		return signal(EventPhoneReachable)
	case *events.ListenFatalError:
		return []Event{textEvent(EventFatalError, e.Error.Error())}
	case *events.ListenTemporaryError:
		return []Event{textEvent(EventTransientError, e.Error.Error())}
	case *events.ListenRecovered:
		return signal(EventConnectionRecovered)
	case *events.GaiaLoggedOut, *gmproto.RevokePairData:
		return signal(EventLoggedOut)
	default:
		return nil
	}
}

// IsSessionChange reports whether evt means the persisted session must be re-saved.
func IsSessionChange(evt any) bool {
	switch evt.(type) {
	case *events.PairSuccessful, *events.AuthTokenRefreshed:
		return true
	default:
		return false
	}
}

func translateClientReady(e *events.ClientReady) []Event {
	out := make([]Event, 0, len(e.Conversations)+1)
	for _, conversation := range e.Conversations {
		out = append(out, protoEvents(EventConversation, conversation)...)
	}
	return append(out, Event{Kind: EventInitialSyncDone})
}

func messageKind(m *libgm.WrappedMessage) EventKind {
	if m.IsOld {
		return EventHistoricalMessage
	}
	return EventMessage
}

func protoEvents(kind EventKind, m proto.Message) []Event {
	payload, err := proto.Marshal(m)
	if err != nil {
		logger.Err(err).Int32("kind", int32(kind)).Msg("dropping event that failed to marshal")
		return nil
	}
	return []Event{{Kind: kind, Payload: payload}}
}

func jsonEvent(kind EventKind, v any) Event {
	payload, _ := json.Marshal(v) // maps of strings cannot fail to marshal
	return Event{Kind: kind, Payload: payload}
}

func textEvent(kind EventKind, text string) Event {
	return Event{Kind: kind, Payload: []byte(text)}
}

func signal(kind EventKind) []Event {
	return []Event{{Kind: kind}}
}
