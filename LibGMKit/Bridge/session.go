package main

import (
	"context"
	"encoding/json"
	"fmt"

	"go.mau.fi/util/exhttp"

	"go.mau.fi/mautrix-gmessages/pkg/libgm"
)

// EventSink receives events for the host app. The C callback is one implementation;
// tests use an in-memory one.
type EventSink interface {
	Deliver(Event)
}

// Session owns one libgm client and turns its callbacks into bridge events.
type Session struct {
	client *libgm.Client
	sink   EventSink
	ctx    context.Context
	cancel context.CancelFunc
}

// NewSession builds a session from a saved blob, or a blank one when sessionJSON is empty.
func NewSession(sessionJSON []byte, sink EventSink) (*Session, error) {
	auth, err := decodeAuth(sessionJSON)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithCancel(logger.WithContext(context.Background()))
	s := &Session{sink: sink, ctx: ctx, cancel: cancel}
	s.client = libgm.NewClient(auth, nil, logger, exhttp.ClientSettings{})
	s.client.SetEventHandler(s.onLibGMEvent)
	return s, nil
}

func decodeAuth(sessionJSON []byte) (*libgm.AuthData, error) {
	auth := libgm.NewAuthData()
	if len(sessionJSON) == 0 {
		return auth, nil
	}
	if err := json.Unmarshal(sessionJSON, auth); err != nil {
		return nil, fmt.Errorf("decode saved session: %w", err)
	}
	return auth, nil
}

// StartQRPairing begins phone pairing and emits EventQRCode.
func (s *Session) StartQRPairing() error {
	if err := s.client.FetchConfig(s.ctx); err != nil {
		return fmt.Errorf("fetch config: %w", err)
	}
	qr, err := s.client.StartLogin(s.ctx)
	if err != nil {
		return fmt.Errorf("start pairing: %w", err)
	}
	s.sink.Deliver(textEvent(EventQRCode, qr))
	return nil
}

// RefreshQRCode emits a new EventQRCode; QR codes expire after roughly 30 seconds.
func (s *Session) RefreshQRCode() error {
	qr, err := s.client.RefreshPhoneRelay()
	if err != nil {
		return fmt.Errorf("refresh QR code: %w", err)
	}
	s.sink.Deliver(textEvent(EventQRCode, qr))
	return nil
}

// StartGoogleAccountPairing pairs via a signed-in Google account; blocks until done.
func (s *Session) StartGoogleAccountPairing(cookies map[string]string) error {
	s.client.AuthData.SetCookies(cookies)
	if err := s.client.FetchConfig(s.ctx); err != nil {
		return fmt.Errorf("fetch config: %w", err)
	}
	onEmoji := func(emoji string) { s.sink.Deliver(textEvent(EventGoogleAccountEmoji, emoji)) }
	if err := s.client.DoGaiaPairing(s.ctx, onEmoji); err != nil {
		return fmt.Errorf("google account pairing: %w", err)
	}
	s.deliverSession()
	return nil
}

func (s *Session) Connect() error {
	// Google rotates account cookies, and this refreshes them and the session ID. Without
	// it a saved login is rejected as soon as it reconnects. Failing here isn't fatal.
	if err := s.client.FetchConfig(s.ctx); err != nil {
		logger.Warn().Err(err).Msg("could not fetch config before connecting")
	} else {
		s.deliverSession()
	}
	if err := s.client.Connect(s.ctx); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	return nil
}

func (s *Session) Disconnect() { s.client.Disconnect() }

func (s *Session) Unpair() error {
	if err := s.client.Unpair(s.ctx); err != nil {
		return fmt.Errorf("unpair: %w", err)
	}
	return nil
}

// Call runs one RPC from the method table.
func (s *Session) Call(method Method, request []byte) ([]byte, error) {
	return Dispatch(s.ctx, s.client, method, request)
}

// Close stops all background work. The session must not be used afterwards.
func (s *Session) Close() {
	s.cancel()
	s.client.Disconnect()
}

func (s *Session) onLibGMEvent(evt any) {
	if IsSessionChange(evt) {
		s.deliverSession()
	}
	for _, e := range TranslateEvent(evt) {
		s.sink.Deliver(e)
	}
}

func (s *Session) deliverSession() {
	blob, err := json.Marshal(s.client.AuthData)
	if err != nil {
		logger.Err(err).Msg("could not encode session for saving")
		return
	}
	s.sink.Deliver(Event{Kind: EventSessionUpdated, Payload: blob})
}
