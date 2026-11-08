// Package main is the C ABI bridge between libgm (Go) and the Swift app.
//
// Contract:
//   - Every request and every event crosses the boundary as protobuf bytes
//     (gmproto types, generated on the Swift side with swift-protobuf from the
//     same .proto files) or, for the few bridge-only payloads, small JSON.
//   - Calls are synchronous and blocking. Swift calls them from a background
//     Task, never the main actor.
//   - Events arrive on a single C callback from Go-owned threads. Swift must
//     copy the bytes before returning; Go frees them after the callback.
//   - Every buffer Go hands to Swift as a return value is freed with gm_free.
//
// Build: see build-xcframework.sh (c-archive per arch, lipo, xcframework).
package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef void (*gm_event_cb)(void *ctx, int32_t kind, const uint8_t *data, int64_t len);

static inline void gm_invoke_cb(gm_event_cb cb, void *ctx, int32_t kind, const uint8_t *data, int64_t len) {
	if (cb) cb(ctx, kind, data, len);
}
*/
import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sync"
	"sync/atomic"
	"unsafe"

	"github.com/rs/zerolog"
	"go.mau.fi/util/exhttp"
	"google.golang.org/protobuf/proto"

	"go.mau.fi/mautrix-gmessages/pkg/libgm"
	"go.mau.fi/mautrix-gmessages/pkg/libgm/events"
	"go.mau.fi/mautrix-gmessages/pkg/libgm/gmproto"
)

// Event kinds. Keep in sync with GMEventKind in Swift.
const (
	evQR                   = 1  // utf8: QR URL to render
	evPairSuccess          = 2  // json: {"phone_id": "..."}
	evAuthUpdated          = 3  // json: AuthData, persist to Keychain
	evReady                = 4  // empty: initial conversations have been sent as evConversation
	evConversation         = 5  // proto: gmproto.Conversation
	evMessage              = 6  // proto: gmproto.Message, live
	evMessageOld           = 7  // proto: gmproto.Message from backfill/resync
	evTyping               = 8  // proto: gmproto.TypingData
	evSettings             = 9  // proto: gmproto.Settings
	evPhoneNotResponding   = 10 // empty
	evPhoneRespondingAgain = 11 // empty
	evFatal                = 12 // utf8: error text; session is dead, re-pair
	evTemporaryError       = 13 // utf8: error text; libgm will retry
	evRecovered            = 14 // empty
	evLoggedOut            = 15 // empty: unpaired from phone or Google account
	evGaiaEmoji            = 16 // utf8: emoji to confirm on the phone (Google-account pairing)
)

// Method ids for gm_call. Keep in sync with GMMethod in Swift.
const (
	mListConversations  = 1  // req ListConversationsRequest -> ListConversationsResponse
	mFetchMessages      = 2  // req bridge json {conversation_id, count, cursor_id, cursor_ts} -> ListMessagesResponse
	mSendMessage        = 3  // req SendMessageRequest -> SendMessageResponse
	mSendReaction       = 4  // req SendReactionRequest -> SendReactionResponse
	mMarkRead           = 5  // req bridge json {conversation_id, message_id} -> empty
	mListContacts       = 6  // req empty -> ListContactsResponse
	mGetOrCreateConv    = 7  // req GetOrCreateConversationRequest -> GetOrCreateConversationResponse
	mParticipantThumbs  = 8  // req bridge json {ids: [...]} -> GetThumbnailResponse
	mFullSizeImage      = 9  // req bridge json {message_id, action_message_id} -> GetFullSizeImageResponse
	mDeleteMessage      = 10 // req bridge json {message_id} -> DeleteMessageResponse
	mGetConversation    = 11 // req bridge json {conversation_id} -> Conversation
	mUpdateConversation = 12 // req UpdateConversationRequest -> UpdateConversationResponse
)

type session struct {
	mu     sync.RWMutex // held for read while calling back into Swift; write-locked on free
	closed bool
	client *libgm.Client
	cb     C.gm_event_cb
	ctx    unsafe.Pointer
	bg     context.Context
	cancel context.CancelFunc
}

var (
	sessions   sync.Map // int64 -> *session
	nextHandle atomic.Int64
	logger     = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).With().Timestamp().Str("component", "libgm").Logger()
)

func (s *session) emit(kind int32, data []byte) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.closed {
		return // Swift may have released the context pointer
	}
	var p *C.uint8_t
	if len(data) > 0 {
		cbuf := C.CBytes(data)
		defer C.free(cbuf)
		p = (*C.uint8_t)(cbuf)
	}
	C.gm_invoke_cb(s.cb, s.ctx, C.int32_t(kind), p, C.int64_t(len(data)))
}

func (s *session) emitProto(kind int32, m proto.Message) {
	b, err := proto.Marshal(m)
	if err != nil {
		logger.Err(err).Msg("marshal event")
		return
	}
	s.emit(kind, b)
}

func (s *session) emitAuth() {
	b, err := json.Marshal(s.client.AuthData)
	if err != nil {
		logger.Err(err).Msg("marshal auth")
		return
	}
	s.emit(evAuthUpdated, b)
}

func (s *session) handle(evt any) {
	switch e := evt.(type) {
	case *events.ClientReady:
		for _, c := range e.Conversations {
			s.emitProto(evConversation, c)
		}
		s.emit(evReady, nil)
	case *events.PairSuccessful:
		b, _ := json.Marshal(map[string]string{"phone_id": e.PhoneID})
		s.emit(evPairSuccess, b)
		s.emitAuth()
	case *events.AuthTokenRefreshed:
		s.emitAuth()
	case *gmproto.Conversation:
		s.emitProto(evConversation, e)
	case *libgm.WrappedMessage:
		if e.IsOld {
			s.emitProto(evMessageOld, e.Message)
		} else {
			s.emitProto(evMessage, e.Message)
		}
	case *gmproto.TypingData:
		s.emitProto(evTyping, e)
	case *gmproto.Settings:
		s.emitProto(evSettings, e)
	case *events.PhoneNotResponding:
		s.emit(evPhoneNotResponding, nil)
	case *events.PhoneRespondingAgain:
		s.emit(evPhoneRespondingAgain, nil)
	case *events.ListenFatalError:
		s.emit(evFatal, []byte(e.Error.Error()))
	case *events.ListenTemporaryError:
		s.emit(evTemporaryError, []byte(e.Error.Error()))
	case *events.ListenRecovered:
		s.emit(evRecovered, nil)
	case *events.GaiaLoggedOut, *gmproto.RevokePairData:
		s.emit(evLoggedOut, nil)
	default:
		logger.Debug().Type("event_type", evt).Msg("unhandled event")
	}
}

func get(h C.int64_t) (*session, error) {
	v, ok := sessions.Load(int64(h))
	if !ok {
		return nil, errors.New("unknown session handle")
	}
	return v.(*session), nil
}

// errOut writes an error string into *out (caller frees) and returns -1.
func errOut(err error, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	msg := []byte(err.Error())
	*out = (*C.uint8_t)(C.CBytes(msg))
	*outLen = C.int64_t(len(msg))
	return -1
}

func okOut(b []byte, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	if len(b) == 0 {
		*out, *outLen = nil, 0
		return 0
	}
	*out = (*C.uint8_t)(C.CBytes(b))
	*outLen = C.int64_t(len(b))
	return 0
}

//export gm_free
func gm_free(p unsafe.Pointer) { C.free(p) }

// gm_session_new creates a client. authJSON may be empty for a fresh pairing.
// Returns a handle > 0, or 0 on failure.
//
//export gm_session_new
func gm_session_new(authJSON *C.uint8_t, authLen C.int64_t, cb C.gm_event_cb, cbCtx unsafe.Pointer) C.int64_t {
	auth := libgm.NewAuthData()
	if authLen > 0 {
		raw := C.GoBytes(unsafe.Pointer(authJSON), C.int(authLen))
		if err := json.Unmarshal(raw, auth); err != nil {
			logger.Err(err).Msg("bad auth json")
			return 0
		}
	}
	bg, cancel := context.WithCancel(logger.WithContext(context.Background()))
	s := &session{cb: cb, ctx: cbCtx, bg: bg, cancel: cancel}
	s.client = libgm.NewClient(auth, nil, logger, exhttp.ClientSettings{})
	s.client.SetEventHandler(s.handle)
	h := nextHandle.Add(1)
	sessions.Store(h, s)
	return C.int64_t(h)
}

//export gm_session_free
func gm_session_free(h C.int64_t) {
	if s, err := get(h); err == nil {
		sessions.Delete(int64(h))
		// Waits for any in-flight callback to finish, then guarantees no more.
		s.mu.Lock()
		s.closed = true
		s.mu.Unlock()
		s.cancel()
		s.client.Disconnect()
	}
}

// gm_start_qr_pairing fetches config and emits evQR. Call gm_refresh_qr every ~30s
// until evPairSuccess arrives.
//
//export gm_start_qr_pairing
func gm_start_qr_pairing(h C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	s, err := get(h)
	if err != nil {
		return errOut(err, out, outLen)
	}
	if err := s.client.FetchConfig(s.bg); err != nil {
		return errOut(fmt.Errorf("fetch config: %w", err), out, outLen)
	}
	qr, err := s.client.StartLogin(s.bg)
	if err != nil {
		return errOut(fmt.Errorf("start login: %w", err), out, outLen)
	}
	s.emit(evQR, []byte(qr))
	return okOut(nil, out, outLen)
}

//export gm_refresh_qr
func gm_refresh_qr(h C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	s, err := get(h)
	if err != nil {
		return errOut(err, out, outLen)
	}
	qr, err := s.client.RefreshPhoneRelay()
	if err != nil {
		return errOut(err, out, outLen)
	}
	s.emit(evQR, []byte(qr))
	return okOut(nil, out, outLen)
}

// gm_start_google_pairing runs Google-account pairing; blocks until done.
// Requires auth cookies already set (from a WKWebView sign-in) in the auth JSON.
//
//export gm_start_google_pairing
func gm_start_google_pairing(h C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	s, err := get(h)
	if err != nil {
		return errOut(err, out, outLen)
	}
	if err := s.client.FetchConfig(s.bg); err != nil {
		return errOut(fmt.Errorf("fetch config: %w", err), out, outLen)
	}
	err = s.client.DoGaiaPairing(s.bg, func(emoji string) { s.emit(evGaiaEmoji, []byte(emoji)) })
	if err != nil {
		return errOut(err, out, outLen)
	}
	s.emitAuth()
	return okOut(nil, out, outLen)
}

// gm_set_cookies sets Google sign-in cookies (JSON object name -> value) before
// gm_start_google_pairing. Swift collects them from a WKWebView sign-in.
//
//export gm_set_cookies
func gm_set_cookies(h C.int64_t, cookiesJSON *C.uint8_t, cookiesLen C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	s, err := get(h)
	if err != nil {
		return errOut(err, out, outLen)
	}
	var cookies map[string]string
	if err := json.Unmarshal(C.GoBytes(unsafe.Pointer(cookiesJSON), C.int(cookiesLen)), &cookies); err != nil {
		return errOut(err, out, outLen)
	}
	s.client.AuthData.SetCookies(cookies)
	return okOut(nil, out, outLen)
}

//export gm_connect
func gm_connect(h C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	s, err := get(h)
	if err != nil {
		return errOut(err, out, outLen)
	}
	if err := s.client.Connect(s.bg); err != nil {
		return errOut(err, out, outLen)
	}
	return okOut(nil, out, outLen)
}

//export gm_disconnect
func gm_disconnect(h C.int64_t) {
	if s, err := get(h); err == nil {
		s.client.Disconnect()
	}
}

//export gm_unpair
func gm_unpair(h C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	s, err := get(h)
	if err != nil {
		return errOut(err, out, outLen)
	}
	if err := s.client.Unpair(s.bg); err != nil {
		return errOut(err, out, outLen)
	}
	return okOut(nil, out, outLen)
}

// gm_call runs one RPC. req is protobuf (or bridge JSON, per method table).
// On success *out holds protobuf response bytes; on failure, error text. Free with gm_free.
//
//export gm_call
func gm_call(h C.int64_t, method C.int32_t, req *C.uint8_t, reqLen C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	s, err := get(h)
	if err != nil {
		return errOut(err, out, outLen)
	}
	var in []byte
	if reqLen > 0 {
		in = C.GoBytes(unsafe.Pointer(req), C.int(reqLen))
	}
	resp, err := dispatch(s.bg, s.client, int(method), in)
	if err != nil {
		return errOut(err, out, outLen)
	}
	if resp == nil {
		return okOut(nil, out, outLen)
	}
	b, err := proto.Marshal(resp)
	if err != nil {
		return errOut(err, out, outLen)
	}
	return okOut(b, out, outLen)
}

func dispatch(ctx context.Context, c *libgm.Client, method int, in []byte) (proto.Message, error) {
	unmarshal := func(m proto.Message) error { return proto.Unmarshal(in, m) }
	switch method {
	case mListConversations:
		req := &gmproto.ListConversationsRequest{}
		if err := unmarshal(req); err != nil {
			return nil, err
		}
		return c.ListConversations(ctx, req)
	case mFetchMessages:
		var r struct {
			ConversationID string `json:"conversation_id"`
			Count          int64  `json:"count"`
			CursorID       string `json:"cursor_id"`
			CursorTS       int64  `json:"cursor_ts"`
		}
		if err := json.Unmarshal(in, &r); err != nil {
			return nil, err
		}
		var cur *gmproto.Cursor
		if r.CursorID != "" {
			cur = &gmproto.Cursor{LastItemID: r.CursorID, LastItemTimestamp: r.CursorTS}
		}
		return c.FetchMessages(ctx, r.ConversationID, r.Count, cur)
	case mSendMessage:
		req := &gmproto.SendMessageRequest{}
		if err := unmarshal(req); err != nil {
			return nil, err
		}
		return c.SendMessage(ctx, req)
	case mSendReaction:
		req := &gmproto.SendReactionRequest{}
		if err := unmarshal(req); err != nil {
			return nil, err
		}
		return c.SendReaction(ctx, req)
	case mMarkRead:
		var r struct {
			ConversationID string `json:"conversation_id"`
			MessageID      string `json:"message_id"`
		}
		if err := json.Unmarshal(in, &r); err != nil {
			return nil, err
		}
		return nil, c.MarkRead(ctx, r.ConversationID, r.MessageID)
	case mListContacts:
		return c.ListContacts(ctx)
	case mGetOrCreateConv:
		req := &gmproto.GetOrCreateConversationRequest{}
		if err := unmarshal(req); err != nil {
			return nil, err
		}
		return c.GetOrCreateConversation(ctx, req)
	case mParticipantThumbs:
		var r struct {
			IDs []string `json:"ids"`
		}
		if err := json.Unmarshal(in, &r); err != nil {
			return nil, err
		}
		return c.GetParticipantThumbnail(ctx, r.IDs...)
	case mFullSizeImage:
		var r struct {
			MessageID       string `json:"message_id"`
			ActionMessageID string `json:"action_message_id"`
		}
		if err := json.Unmarshal(in, &r); err != nil {
			return nil, err
		}
		return c.GetFullSizeImage(ctx, r.MessageID, r.ActionMessageID)
	case mDeleteMessage:
		var r struct {
			MessageID string `json:"message_id"`
		}
		if err := json.Unmarshal(in, &r); err != nil {
			return nil, err
		}
		return c.DeleteMessage(ctx, r.MessageID)
	case mGetConversation:
		var r struct {
			ConversationID string `json:"conversation_id"`
		}
		if err := json.Unmarshal(in, &r); err != nil {
			return nil, err
		}
		return c.GetConversation(ctx, r.ConversationID)
	case mUpdateConversation:
		req := &gmproto.UpdateConversationRequest{}
		if err := unmarshal(req); err != nil {
			return nil, err
		}
		return c.UpdateConversation(ctx, req)
	}
	return nil, fmt.Errorf("unknown method %d", method)
}

func main() {}
