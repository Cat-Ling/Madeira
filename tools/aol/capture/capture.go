// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package capture

import (
	"context"
	"errors"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

// ErrUnsupportedPlatform is returned when local hardware capture is not
// implemented on the host OS.
var ErrUnsupportedPlatform = errors.New("raw hardware capture is not supported on this platform")

// Options controls which local input classes are captured.
type Options struct {
	Keyboard bool
	Mouse    bool
	Gamepad  bool
	Grab     bool
	Rumble   bool
	OnEvent  func(Event)
}

// EventKind distinguishes captured input messages emitted by a Capturer.
type EventKind uint8

const (
	EventKey EventKind = iota + 1
	EventMouseMotion
	EventMouseButton
	EventGamepad
	EventCaptureToggled
)

// Event represents one normalized hardware input or capture-state update.
type Event struct {
	Kind    EventKind
	Grabbed bool
	Key     protocol.KeyEvent
	Mouse   protocol.MouseMotion
	Buttons protocol.MouseButton
	Gamepad protocol.GamepadState
}

// Summary describes the physical devices currently attached to the Capturer.
type Summary struct {
	Keyboards int
	Mice      int
	Gamepads  int
	Grabbed   bool
}

// Capturer streams local desktop input events and accepts controller rumble.
type Capturer interface {
	Run(ctx context.Context) error
	SetRumble(slot uint8, left, right uint16) error
	Summary() Summary
}

// NormalizeAxis maps a signed input axis with arbitrary [min, max] bounds into
// XInput's signed int16 range [-32768, 32767]. When invert is true, polarity flips
// (needed on Linux evdev where +Y points downward rather than upward).
func NormalizeAxis(val, minVal, maxVal int32, invert bool) int16 {
	if maxVal <= minVal {
		return 0
	}
	clamped := val
	if clamped < minVal {
		clamped = minVal
	} else if clamped > maxVal {
		clamped = maxVal
	}
	norm := float64(clamped-minVal)/float64(maxVal-minVal)*2.0 - 1.0
	if invert {
		norm = -norm
	}
	if norm <= -1.0 {
		return -32768
	}
	if norm >= 1.0 {
		return 32767
	}
	if norm < 0 {
		return int16(norm * 32768.0)
	}
	return int16(norm * 32767.0)
}

// NormalizeTrigger maps an unsigned axis range [min, max] into uint8 [0, 255].
func NormalizeTrigger(val, minVal, maxVal int32) uint8 {
	if maxVal <= minVal {
		return 0
	}
	clamped := val
	if clamped < minVal {
		clamped = minVal
	} else if clamped > maxVal {
		clamped = maxVal
	}
	scaled := float64(clamped-minVal) / float64(maxVal-minVal) * 255.0
	if scaled <= 0 {
		return 0
	}
	if scaled >= 255 {
		return 255
	}
	return uint8(scaled + 0.5)
}
