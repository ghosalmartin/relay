package main

import (
	"testing"

	"github.com/rs/zerolog"
)

func TestLogLevelFrom_StaysQuietUnlessAskedOtherwise(t *testing.T) {
	cases := map[string]zerolog.Level{
		"":         zerolog.InfoLevel,
		"nonsense": zerolog.InfoLevel,
		"trace":    zerolog.TraceLevel,
		"debug":    zerolog.DebugLevel,
	}
	for value, want := range cases {
		if got := logLevelFrom(value); got != want {
			t.Errorf("logLevelFrom(%q) = %v, want %v", value, got, want)
		}
	}
}
