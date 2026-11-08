package main

import "testing"

func TestRegistry_HandlesAreUniqueAndNotReused(t *testing.T) {
	var r registry[string]
	first := r.add("a")
	r.remove(first)
	second := r.add("b")

	if first == second {
		t.Fatalf("handle %d was reused", first)
	}
	if _, err := r.get(first); err != errUnknownHandle {
		t.Fatalf("stale handle err = %v, want errUnknownHandle", err)
	}
	if v, _ := r.get(second); v != "b" {
		t.Fatalf("get = %q, want b", v)
	}
}

func TestRegistry_RemoveReturnsValueOnce(t *testing.T) {
	var r registry[string]
	h := r.add("a")

	if v, ok := r.remove(h); !ok || v != "a" {
		t.Fatalf("first remove = %q, %v", v, ok)
	}
	if _, ok := r.remove(h); ok {
		t.Fatal("second remove should report nothing removed")
	}
}
