// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package capture_test

import (
	"encoding/binary"
	"testing"

	"github.com/Cat-Ling/Madeira/tools/aol/capture"
)

func TestNormalizeAxisAndTrigger(t *testing.T) {
	t.Parallel()

	if got := capture.NormalizeAxis(0, -32768, 32767, false); got != 0 {
		t.Fatalf("center axis = %d, want 0", got)
	}
	if got := capture.NormalizeAxis(-32768, -32768, 32767, false); got != -32768 {
		t.Fatalf("min axis = %d, want -32768", got)
	}
	if got := capture.NormalizeAxis(255, 0, 255, true); got != -32768 {
		t.Fatalf("inverted max 0..255 = %d, want -32768", got)
	}
	if got := capture.NormalizeTrigger(255, 0, 255); got != 255 {
		t.Fatalf("max trigger = %d, want 255", got)
	}
	if got := capture.NormalizeTrigger(0, 0, 255); got != 0 {
		t.Fatalf("min trigger = %d, want 0", got)
	}
}

func makeRawEv24(typ, code uint16, val int32) []byte {
	b := make([]byte, 24)
	binary.LittleEndian.PutUint16(b[16:18], typ)
	binary.LittleEndian.PutUint16(b[18:20], code)
	binary.LittleEndian.PutUint32(b[20:24], uint32(val))
	return b
}
