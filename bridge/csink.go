package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef void (*gm_event_cb)(void *ctx, int32_t kind, const uint8_t *data, int64_t len);

static inline void gm_invoke_event_cb(gm_event_cb cb, void *ctx, int32_t kind, const uint8_t *data, int64_t len) {
	if (cb) cb(ctx, kind, data, len);
}
*/
import "C"

import (
	"sync"
	"unsafe"
)

// cSink delivers events to the host app through its C callback.
// Close blocks until any in-flight callback returns, and no callback runs after it,
// so the host can safely release the context pointer once Close returns.
type cSink struct {
	mu       sync.RWMutex
	closed   bool
	callback C.gm_event_cb
	context  unsafe.Pointer
}

func newCSink(callback C.gm_event_cb, context unsafe.Pointer) *cSink {
	return &cSink{callback: callback, context: context}
}

func (s *cSink) Deliver(e Event) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.closed {
		return
	}
	data, free := cBytes(e.Payload)
	defer free()
	C.gm_invoke_event_cb(s.callback, s.context, C.int32_t(e.Kind), data, C.int64_t(len(e.Payload)))
}

func (s *cSink) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closed = true
}

// cBytes copies b into C memory. The callback only borrows it; free releases it.
func cBytes(b []byte) (*C.uint8_t, func()) {
	if len(b) == 0 {
		return nil, func() {}
	}
	p := C.CBytes(b)
	return (*C.uint8_t)(p), func() { C.free(p) }
}
