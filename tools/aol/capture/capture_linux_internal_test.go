// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

//go:build linux

package capture

import "testing"

func TestLinuxGrabDeferUntilChordReleased(t *testing.T) {
	t.Parallel()

	var (
		grabs   []bool
		toggles []bool
		keyEvs  int
	)
	dev := &linuxDevice{isKB: true}
	cap := &linuxCapturer{
		opts: Options{
			Keyboard: true,
			Grab:     true,
			OnEvent: func(ev Event) {
				switch ev.Kind {
				case EventCaptureToggled:
					toggles = append(toggles, ev.Grabbed)
				case EventKey:
					keyEvs++
				}
			},
		},
		grabbed:     true,
		desiredGrab: true,
		connected:   true,
		heldEv:      make(map[evdevKey]struct{}),
		grabFn: func(on bool) {
			grabs = append(grabs, on)
		},
	}

	// Press Ctrl+Alt+G while grabbed: forwarding stops immediately, but EVIOCGRAB
	// must stay active until all chord keys are released.
	cap.processDeviceBatch(dev, []RawInputEvent{
		{Type: evKey, Code: 29, Value: 1}, // KEY_LEFTCTRL down
		{Type: evKey, Code: 56, Value: 1}, // KEY_LEFTALT down
		{Type: evKey, Code: 34, Value: 1}, // KEY_G down
		{Type: evSyn, Code: 0, Value: 0},
	})
	if len(toggles) != 1 || toggles[0] != false {
		t.Fatalf("toggles after ungrab chord = %v, want [false]", toggles)
	}
	if len(grabs) != 0 {
		t.Fatalf("grabs changed prematurely while chord held: %v", grabs)
	}

	// Repeat events on G while still held must not release grab or re-toggle.
	cap.processDeviceBatch(dev, []RawInputEvent{
		{Type: evKey, Code: 34, Value: 2},
		{Type: evSyn, Code: 0, Value: 0},
	})
	if len(grabs) != 0 || len(toggles) != 1 {
		t.Fatalf("repeat altered grab state: grabs=%v toggles=%v", grabs, toggles)
	}

	// Releasing G and Alt is not enough while Ctrl is still held.
	cap.processDeviceBatch(dev, []RawInputEvent{
		{Type: evKey, Code: 34, Value: 0},
		{Type: evKey, Code: 56, Value: 0},
		{Type: evSyn, Code: 0, Value: 0},
	})
	if len(grabs) != 0 {
		t.Fatalf("ungrabbed before final key release: %v", grabs)
	}

	// Releasing final Ctrl completes ungrab cleanly.
	cap.processDeviceBatch(dev, []RawInputEvent{
		{Type: evKey, Code: 29, Value: 0},
		{Type: evSyn, Code: 0, Value: 0},
	})
	if len(grabs) != 1 || grabs[0] != false {
		t.Fatalf("grabs after releasing ungrab chord = %v, want [false]", grabs)
	}

	// Now ungrabbed: pressing Ctrl+Alt+G must NOT call EVIOCGRAB=1 until all
	// chord keys are released, so host OS receives every key-up.
	keyEvs = 0
	cap.processDeviceBatch(dev, []RawInputEvent{
		{Type: evKey, Code: 29, Value: 1},
		{Type: evKey, Code: 56, Value: 1},
		{Type: evKey, Code: 34, Value: 1},
		{Type: evSyn, Code: 0, Value: 0},
	})
	if len(grabs) != 1 || len(toggles) != 1 {
		t.Fatalf("re-grabbed prematurely on key-down: grabs=%v toggles=%v", grabs, toggles)
	}

	cap.processDeviceBatch(dev, []RawInputEvent{
		{Type: evKey, Code: 34, Value: 0},
		{Type: evKey, Code: 56, Value: 0},
		{Type: evSyn, Code: 0, Value: 0},
	})
	if len(grabs) != 1 || len(toggles) != 1 {
		t.Fatalf("re-grabbed while Ctrl still held: grabs=%v toggles=%v", grabs, toggles)
	}

	cap.processDeviceBatch(dev, []RawInputEvent{
		{Type: evKey, Code: 29, Value: 0},
		{Type: evSyn, Code: 0, Value: 0},
	})
	if len(grabs) != 2 || grabs[1] != true {
		t.Fatalf("grabs after releasing re-grab chord = %v, want [false true]", grabs)
	}
	if len(toggles) != 2 || toggles[1] != true {
		t.Fatalf("toggles after releasing re-grab chord = %v, want [false true]", toggles)
	}
	if keyEvs != 0 {
		t.Fatalf("re-grab chord leaked %d key events to Madeira", keyEvs)
	}
}
