package main

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"google.golang.org/protobuf/proto"

	"go.mau.fi/mautrix-gmessages/pkg/libgm/gmproto"
)

func TestDispatch_ProtoRequestIsDecodedAndResponseEncoded(t *testing.T) {
	api := &fakeAPI{sendResponse: &gmproto.SendMessageResponse{}}
	request := mustProto(t, &gmproto.SendMessageRequest{ConversationID: "c1"})

	_, err := Dispatch(context.Background(), api, MethodSendMessage, request)

	if err != nil {
		t.Fatal(err)
	}
	if api.sentConversationID != "c1" {
		t.Fatalf("sent to %q, want c1", api.sentConversationID)
	}
}

func TestDispatch_FetchMessagesBuildsCursorOnlyWhenGiven(t *testing.T) {
	api := &fakeAPI{}

	mustDispatch(t, api, MethodFetchMessages, fetchMessagesRequest{ConversationID: "c1", Count: 20})
	if api.fetchCursor != nil {
		t.Fatal("first page should have no cursor")
	}

	mustDispatch(t, api, MethodFetchMessages, fetchMessagesRequest{ConversationID: "c1", Count: 20, CursorID: "m9", CursorTimestamp: 42})
	if api.fetchCursor.GetLastItemID() != "m9" || api.fetchCursor.GetLastItemTimestamp() != 42 {
		t.Fatalf("cursor = %v, want m9@42", api.fetchCursor)
	}
}

func TestDispatch_CallWithNoResponseBodyReturnsNil(t *testing.T) {
	api := &fakeAPI{}

	got := mustDispatch(t, api, MethodMarkRead, markReadRequest{ConversationID: "c1", MessageID: "m1"})

	if got != nil {
		t.Fatalf("got %d bytes, want nil", len(got))
	}
	if api.markedRead != "c1/m1" {
		t.Fatalf("marked %q, want c1/m1", api.markedRead)
	}
}

func TestDispatch_PropagatesLibraryErrors(t *testing.T) {
	api := &fakeAPI{err: errors.New("phone offline")}

	_, err := Dispatch(context.Background(), api, MethodListContacts, nil)

	if err == nil || err.Error() != "phone offline" {
		t.Fatalf("err = %v, want phone offline", err)
	}
}

func TestDispatch_RejectsUnknownMethod(t *testing.T) {
	if _, err := Dispatch(context.Background(), &fakeAPI{}, Method(999), nil); err == nil {
		t.Fatal("want error for unknown method")
	}
}

func TestDispatch_RejectsMalformedRequest(t *testing.T) {
	if _, err := Dispatch(context.Background(), &fakeAPI{}, MethodMarkRead, []byte("{nope")); err == nil {
		t.Fatal("want error for malformed request")
	}
}

func TestEveryMethodHasAHandler(t *testing.T) {
	for m := MethodListConversations; m <= MethodUpdateConversation; m++ {
		if _, ok := handlers[m]; !ok {
			t.Errorf("method %d has no handler", m)
		}
	}
}

func mustDispatch(t *testing.T, api MessagesAPI, m Method, request any) []byte {
	t.Helper()
	body, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Dispatch(context.Background(), api, m, body)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

func mustProto(t *testing.T, m proto.Message) []byte {
	t.Helper()
	b, err := proto.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// fakeAPI records what Dispatch asked for. Methods the tests don't exercise return empty values.
type fakeAPI struct {
	err                error
	sendResponse       *gmproto.SendMessageResponse
	sentConversationID string
	fetchCursor        *gmproto.Cursor
	markedRead         string
}

func (f *fakeAPI) ListConversations(context.Context, *gmproto.ListConversationsRequest) (*gmproto.ListConversationsResponse, error) {
	return &gmproto.ListConversationsResponse{}, f.err
}

func (f *fakeAPI) FetchMessages(_ context.Context, _ string, _ int64, cursor *gmproto.Cursor) (*gmproto.ListMessagesResponse, error) {
	f.fetchCursor = cursor
	return &gmproto.ListMessagesResponse{}, f.err
}

func (f *fakeAPI) SendMessage(_ context.Context, r *gmproto.SendMessageRequest) (*gmproto.SendMessageResponse, error) {
	f.sentConversationID = r.GetConversationID()
	return f.sendResponse, f.err
}

func (f *fakeAPI) SendReaction(context.Context, *gmproto.SendReactionRequest) (*gmproto.SendReactionResponse, error) {
	return &gmproto.SendReactionResponse{}, f.err
}

func (f *fakeAPI) MarkRead(_ context.Context, conversationID, messageID string) error {
	f.markedRead = conversationID + "/" + messageID
	return f.err
}

func (f *fakeAPI) ListContacts(context.Context) (*gmproto.ListContactsResponse, error) {
	if f.err != nil {
		return nil, f.err
	}
	return &gmproto.ListContactsResponse{}, nil
}

func (f *fakeAPI) GetOrCreateConversation(context.Context, *gmproto.GetOrCreateConversationRequest) (*gmproto.GetOrCreateConversationResponse, error) {
	return &gmproto.GetOrCreateConversationResponse{}, f.err
}

func (f *fakeAPI) GetParticipantThumbnail(context.Context, ...string) (*gmproto.GetThumbnailResponse, error) {
	return &gmproto.GetThumbnailResponse{}, f.err
}

func (f *fakeAPI) GetFullSizeImage(context.Context, string, string) (*gmproto.GetFullSizeImageResponse, error) {
	return &gmproto.GetFullSizeImageResponse{}, f.err
}

func (f *fakeAPI) DeleteMessage(context.Context, string) (*gmproto.DeleteMessageResponse, error) {
	return &gmproto.DeleteMessageResponse{}, f.err
}

func (f *fakeAPI) GetConversation(context.Context, string) (*gmproto.Conversation, error) {
	return &gmproto.Conversation{}, f.err
}

func (f *fakeAPI) UpdateConversation(context.Context, *gmproto.UpdateConversationRequest) (*gmproto.UpdateConversationResponse, error) {
	return &gmproto.UpdateConversationResponse{}, f.err
}
