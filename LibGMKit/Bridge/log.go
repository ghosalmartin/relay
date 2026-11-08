package main

import (
	"os"

	"github.com/rs/zerolog"
)

// logLevelVariable opts in to verbose logging when debugging the protocol.
const logLevelVariable = "RELAY_BRIDGE_LOG"

// logger writes to stderr, which ends up in Console.app when hosted by the Mac app.
var logger = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr}).
	Level(logLevelFrom(os.Getenv(logLevelVariable))).
	With().Timestamp().Str("component", "bridge").Logger()

// logLevelFrom defaults to Info because libgm's debug and trace output includes
// auth tokens and raw responses, which must not reach the system log.
func logLevelFrom(value string) zerolog.Level {
	level, err := zerolog.ParseLevel(value)
	if err != nil || level == zerolog.NoLevel {
		return zerolog.InfoLevel
	}
	return level
}
