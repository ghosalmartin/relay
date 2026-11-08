// Command bridge is the C ABI between libgm and the host app.
//
// This file holds only the exported functions. Each one converts C arguments to
// Go, delegates to a Session, and converts the result back. No logic lives here.
//
// ABI rules (the Swift side relies on these):
//   - Calls block. The host calls them off its main thread.
//   - Functions that can fail return 0 on success and -1 on failure. On failure
//     *out holds UTF-8 error text; on success it holds the response bytes (or NULL).
//     The host frees *out with gm_free either way.
//   - Events arrive on the callback from Go-owned threads. The payload is only
//     valid for the duration of the callback; the host copies it.
//   - After gm_session_free returns, the callback is never invoked again.
package main

/*
#include <stdint.h>
#include <stdlib.h>
typedef void (*gm_event_cb)(void *ctx, int32_t kind, const uint8_t *data, int64_t len);
*/
import "C"

import (
	"encoding/json"
	"unsafe"
)

const (
	abiOK    C.int32_t = 0
	abiError C.int32_t = -1
)

var sessions registry[*hostedSession]

// hostedSession pairs a Session with the sink that owns the host's callback.
type hostedSession struct {
	*Session
	sink *cSink
}

func main() {}

//export gm_free
func gm_free(p unsafe.Pointer) { C.free(p) }

// gm_session_new returns a handle > 0, or 0 if the saved session could not be decoded.
//
//export gm_session_new
func gm_session_new(sessionJSON *C.uint8_t, sessionLen C.int64_t, callback C.gm_event_cb, context unsafe.Pointer) C.int64_t {
	sink := newCSink(callback, context)
	session, err := NewSession(goBytes(sessionJSON, sessionLen), sink)
	if err != nil {
		logger.Err(err).Msg("could not create session")
		return 0
	}
	return C.int64_t(sessions.add(&hostedSession{Session: session, sink: sink}))
}

//export gm_session_free
func gm_session_free(handle C.int64_t) {
	hosted, ok := sessions.remove(int64(handle))
	if !ok {
		return
	}
	hosted.sink.Close() // first: guarantees no callback after we return
	hosted.Close()
}

//export gm_start_qr_pairing
func gm_start_qr_pairing(handle C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	return run(handle, out, outLen, func(s *hostedSession) ([]byte, error) {
		return nil, s.StartQRPairing()
	})
}

//export gm_refresh_qr
func gm_refresh_qr(handle C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	return run(handle, out, outLen, func(s *hostedSession) ([]byte, error) {
		return nil, s.RefreshQRCode()
	})
}

// gm_start_google_pairing takes the Google sign-in cookies as a JSON object of name to value.
//
//export gm_start_google_pairing
func gm_start_google_pairing(handle C.int64_t, cookiesJSON *C.uint8_t, cookiesLen C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	return run(handle, out, outLen, func(s *hostedSession) ([]byte, error) {
		var cookies map[string]string
		if err := json.Unmarshal(goBytes(cookiesJSON, cookiesLen), &cookies); err != nil {
			return nil, err
		}
		return nil, s.StartGoogleAccountPairing(cookies)
	})
}

//export gm_connect
func gm_connect(handle C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	return run(handle, out, outLen, func(s *hostedSession) ([]byte, error) {
		return nil, s.Connect()
	})
}

//export gm_disconnect
func gm_disconnect(handle C.int64_t) {
	if s, err := sessions.get(int64(handle)); err == nil {
		s.Disconnect()
	}
}

//export gm_unpair
func gm_unpair(handle C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	return run(handle, out, outLen, func(s *hostedSession) ([]byte, error) {
		return nil, s.Unpair()
	})
}

//export gm_call
func gm_call(handle C.int64_t, method C.int32_t, request *C.uint8_t, requestLen C.int64_t, out **C.uint8_t, outLen *C.int64_t) C.int32_t {
	return run(handle, out, outLen, func(s *hostedSession) ([]byte, error) {
		return s.Call(Method(method), goBytes(request, requestLen))
	})
}

// run looks up the session, runs op, and writes the result or error to out.
func run(handle C.int64_t, out **C.uint8_t, outLen *C.int64_t, op func(*hostedSession) ([]byte, error)) C.int32_t {
	result, err := withSession(int64(handle), op)
	if err != nil {
		writeOut([]byte(err.Error()), out, outLen)
		return abiError
	}
	writeOut(result, out, outLen)
	return abiOK
}

func withSession(handle int64, op func(*hostedSession) ([]byte, error)) ([]byte, error) {
	session, err := sessions.get(handle)
	if err != nil {
		return nil, err
	}
	return op(session)
}

func writeOut(b []byte, out **C.uint8_t, outLen *C.int64_t) {
	*outLen = C.int64_t(len(b))
	if len(b) == 0 {
		*out = nil
		return
	}
	*out = (*C.uint8_t)(C.CBytes(b))
}

func goBytes(p *C.uint8_t, n C.int64_t) []byte {
	if p == nil || n <= 0 {
		return nil
	}
	return C.GoBytes(unsafe.Pointer(p), C.int(n))
}
