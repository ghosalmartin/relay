package main

import (
	"errors"
	"sync"
	"sync/atomic"
)

var errUnknownHandle = errors.New("unknown session handle")

// registry maps the opaque int64 handles given to the host app onto live sessions.
// Handles are never reused, so a stale handle fails cleanly instead of hitting another session.
type registry[T any] struct {
	entries sync.Map // int64 -> T
	last    atomic.Int64
}

func (r *registry[T]) add(v T) int64 {
	h := r.last.Add(1)
	r.entries.Store(h, v)
	return h
}

func (r *registry[T]) get(h int64) (T, error) {
	v, ok := r.entries.Load(h)
	if !ok {
		var zero T
		return zero, errUnknownHandle
	}
	return v.(T), nil
}

// remove deletes h and returns what it held, so the caller can close it.
func (r *registry[T]) remove(h int64) (T, bool) {
	v, ok := r.entries.LoadAndDelete(h)
	if !ok {
		var zero T
		return zero, false
	}
	return v.(T), true
}
