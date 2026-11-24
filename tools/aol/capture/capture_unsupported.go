// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

//go:build !linux && !windows

package capture

import "context"

type unsupportedCapturer struct{}

// New returns ErrUnsupportedPlatform on host operating systems without a raw
// kernel/RawInput backend. Protocol and Client remain usable for library callers.
func New(Options) (Capturer, error) {
	return unsupportedCapturer{}, ErrUnsupportedPlatform
}

func (unsupportedCapturer) Run(context.Context) error             { return ErrUnsupportedPlatform }
func (unsupportedCapturer) SetRumble(uint8, uint16, uint16) error { return ErrUnsupportedPlatform }
func (unsupportedCapturer) SetConnected(bool)                     {}
func (unsupportedCapturer) Summary() Summary                      { return Summary{} }
