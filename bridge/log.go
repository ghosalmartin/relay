package main

import (
	"os"

	"github.com/rs/zerolog"
)

// logger writes to stderr, which ends up in Console.app when hosted by the Mac app.
var logger = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).With().Timestamp().Str("component", "bridge").Logger()
