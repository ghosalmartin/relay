package main

import (
	"context"
	"encoding/json"
	"fmt"

	"google.golang.org/protobuf/proto"

	"go.mau.fi/mautrix-gmessages/pkg/libgm/gmproto"
)

// Method identifies an RPC. Values are part of the ABI: keep in sync with
// BridgeMethod in Swift, never renumber.
type Method int32

const (
	MethodListConversations       Method = 1  // gmproto.ListConversationsRequest -> ListConversationsResponse
	MethodFetchMessages           Method = 2  // json fetchMessagesRequest -> ListMessagesResponse
	MethodSendMessage             Method = 3  // gmproto.SendMessageRequest -> SendMessageResponse
	MethodSendReaction            Method = 4  // gmproto.SendReactionRequest -> SendReactionResponse
	MethodMarkRead                Method = 5  // json markReadRequest -> empty
	MethodListContacts            Method = 6  // empty -> ListContactsResponse
	MethodGetOrCreateConversation Method = 7  // gmproto.GetOrCreateConversationRequest -> response
	MethodParticipantThumbnails   Method = 8  // json idsRequest -> GetThumbnailResponse
	MethodFullSizeImage           Method = 9  // json fullSizeImageRequest -> GetFullSizeImageResponse
	MethodDeleteMessage           Method = 10 // json messageRequest -> DeleteMessageResponse
	MethodGetConversation         Method = 11 // json conversationRequest -> Conversation
	MethodUpdateConversation      Method = 12 // gmproto.UpdateConversationRequest -> response
)

// MessagesAPI is the slice of libgm.Client the RPC table needs.
// Depending on this instead of *libgm.Client keeps Dispatch testable.
type MessagesAPI interface {
	ListConversations(context.Context, *gmproto.ListConversationsRequest) (*gmproto.ListConversationsResponse, error)
	FetchMessages(ctx context.Context, conversationID string, count int64, cursor *gmproto.Cursor) (*gmproto.ListMessagesResponse, error)
	SendMessage(context.Context, *gmproto.SendMessageRequest) (*gmproto.SendMessageResponse, error)
	SendReaction(context.Context, *gmproto.SendReactionRequest) (*gmproto.SendReactionResponse, error)
	MarkRead(ctx context.Context, conversationID, messageID string) error
	ListContacts(context.Context) (*gmproto.ListContactsResponse, error)
	GetOrCreateConversation(context.Context, *gmproto.GetOrCreateConversationRequest) (*gmproto.GetOrCreateConversationResponse, error)
	GetParticipantThumbnail(ctx context.Context, participantIDs ...string) (*gmproto.GetThumbnailResponse, error)
	GetFullSizeImage(ctx context.Context, messageID, actionMessageID string) (*gmproto.GetFullSizeImageResponse, error)
	DeleteMessage(ctx context.Context, messageID string) (*gmproto.DeleteMessageResponse, error)
	GetConversation(ctx context.Context, conversationID string) (*gmproto.Conversation, error)
	UpdateConversation(context.Context, *gmproto.UpdateConversationRequest) (*gmproto.UpdateConversationResponse, error)
}

// Bridge-only request shapes for calls whose libgm signature takes plain arguments.
type (
	fetchMessagesRequest struct {
		ConversationID  string `json:"conversation_id"`
		Count           int64  `json:"count"`
		CursorID        string `json:"cursor_id,omitempty"`
		CursorTimestamp int64  `json:"cursor_timestamp,omitempty"`
	}
	markReadRequest struct {
		ConversationID string `json:"conversation_id"`
		MessageID      string `json:"message_id"`
	}
	idsRequest struct {
		IDs []string `json:"ids"`
	}
	fullSizeImageRequest struct {
		MessageID       string `json:"message_id"`
		ActionMessageID string `json:"action_message_id"`
	}
	messageRequest struct {
		MessageID string `json:"message_id"`
	}
	conversationRequest struct {
		ConversationID string `json:"conversation_id"`
	}
)

type handler func(ctx context.Context, api MessagesAPI, request []byte) (proto.Message, error)

var handlers = map[Method]handler{
	MethodListConversations: protoCall(func(ctx context.Context, api MessagesAPI, r *gmproto.ListConversationsRequest) (proto.Message, error) {
		return api.ListConversations(ctx, r)
	}),
	MethodFetchMessages: jsonCall(func(ctx context.Context, api MessagesAPI, r fetchMessagesRequest) (proto.Message, error) {
		return api.FetchMessages(ctx, r.ConversationID, r.Count, r.cursor())
	}),
	MethodSendMessage: protoCall(func(ctx context.Context, api MessagesAPI, r *gmproto.SendMessageRequest) (proto.Message, error) {
		return api.SendMessage(ctx, r)
	}),
	MethodSendReaction: protoCall(func(ctx context.Context, api MessagesAPI, r *gmproto.SendReactionRequest) (proto.Message, error) {
		return api.SendReaction(ctx, r)
	}),
	MethodMarkRead: jsonCall(func(ctx context.Context, api MessagesAPI, r markReadRequest) (proto.Message, error) {
		return nil, api.MarkRead(ctx, r.ConversationID, r.MessageID)
	}),
	MethodListContacts: func(ctx context.Context, api MessagesAPI, _ []byte) (proto.Message, error) {
		return api.ListContacts(ctx)
	},
	MethodGetOrCreateConversation: protoCall(func(ctx context.Context, api MessagesAPI, r *gmproto.GetOrCreateConversationRequest) (proto.Message, error) {
		return api.GetOrCreateConversation(ctx, r)
	}),
	MethodParticipantThumbnails: jsonCall(func(ctx context.Context, api MessagesAPI, r idsRequest) (proto.Message, error) {
		return api.GetParticipantThumbnail(ctx, r.IDs...)
	}),
	MethodFullSizeImage: jsonCall(func(ctx context.Context, api MessagesAPI, r fullSizeImageRequest) (proto.Message, error) {
		return api.GetFullSizeImage(ctx, r.MessageID, r.ActionMessageID)
	}),
	MethodDeleteMessage: jsonCall(func(ctx context.Context, api MessagesAPI, r messageRequest) (proto.Message, error) {
		return api.DeleteMessage(ctx, r.MessageID)
	}),
	MethodGetConversation: jsonCall(func(ctx context.Context, api MessagesAPI, r conversationRequest) (proto.Message, error) {
		return api.GetConversation(ctx, r.ConversationID)
	}),
	MethodUpdateConversation: protoCall(func(ctx context.Context, api MessagesAPI, r *gmproto.UpdateConversationRequest) (proto.Message, error) {
		return api.UpdateConversation(ctx, r)
	}),
}

// Dispatch decodes request for method, calls api, and returns the encoded response
// (nil for calls with no response body).
func Dispatch(ctx context.Context, api MessagesAPI, method Method, request []byte) ([]byte, error) {
	h, ok := handlers[method]
	if !ok {
		return nil, fmt.Errorf("unknown method %d", method)
	}
	response, err := h(ctx, api, request)
	if err != nil {
		return nil, err
	}
	if isNil(response) {
		return nil, nil
	}
	return proto.Marshal(response)
}

func (r fetchMessagesRequest) cursor() *gmproto.Cursor {
	if r.CursorID == "" {
		return nil
	}
	return &gmproto.Cursor{LastItemID: r.CursorID, LastItemTimestamp: r.CursorTimestamp}
}

// protoCall adapts a typed handler whose request is a protobuf message.
func protoCall[R any, PR interface {
	*R
	proto.Message
}](call func(context.Context, MessagesAPI, PR) (proto.Message, error)) handler {
	return func(ctx context.Context, api MessagesAPI, request []byte) (proto.Message, error) {
		r := PR(new(R))
		if err := proto.Unmarshal(request, r); err != nil {
			return nil, fmt.Errorf("decode request: %w", err)
		}
		return call(ctx, api, r)
	}
}

// jsonCall adapts a typed handler whose request is a bridge JSON struct.
func jsonCall[R any](call func(context.Context, MessagesAPI, R) (proto.Message, error)) handler {
	return func(ctx context.Context, api MessagesAPI, request []byte) (proto.Message, error) {
		var r R
		if err := json.Unmarshal(request, &r); err != nil {
			return nil, fmt.Errorf("decode request: %w", err)
		}
		return call(ctx, api, r)
	}
}

// isNil catches typed-nil responses (e.g. a nil *T returned as proto.Message).
func isNil(m proto.Message) bool {
	return m == nil || !m.ProtoReflect().IsValid()
}
