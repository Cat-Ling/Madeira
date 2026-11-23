// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

//go:build linux

package capture_test

import (
	"testing"

	"github.com/Cat-Ling/Madeira/tools/aol/capture"
)

func TestParseLinuxEvents(t *testing.T) {
	t.Parallel()

	var raw []byte
	raw = append(raw, makeRawEv24(1, 30, 1)...) // EV_KEY KEY_A down
	raw = append(raw, makeRawEv24(2, 0, 14)...) // EV_REL REL_X +14
	raw = append(raw, makeRawEv24(0, 0, 0)...)  // EV_SYN

	got := capture.ParseLinuxEvents(raw, 24)
	if len(got) != 3 {
		t.Fatalf("len = %d, want 3", len(got))
	}
	if got[0].Type != 1 || got[0].Code != 30 || got[0].Value != 1 {
		t.Fatalf("ev[0] = %+v, want {1 30 1}", got[0])
	}
	if got[1].Type != 2 || got[1].Code != 0 || got[1].Value != 14 {
		t.Fatalf("ev[1] = %+v, want {2 0 14}", got[1])
	}
	if got[2].Type != 0 || got[2].Code != 0 || got[2].Value != 0 {
		t.Fatalf("ev[2] = %+v, want {0 0 0}", got[2])
	}
}
