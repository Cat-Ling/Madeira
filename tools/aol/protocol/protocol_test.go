// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package protocol_test

import (
	"bytes"
	"errors"
	"reflect"
	"testing"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

func TestRoundTripPackets(t *testing.T) {
	t.Parallel()

	tag := protocol.AuthTag("4242")
	cases := []struct {
		name string
		seq  uint32
		pkt  protocol.Packet
	}{
		{name: "discover", seq: 1, pkt: protocol.Discover{}},
		{name: "announce", seq: 2, pkt: protocol.Announce{Port: 37419, Flags: 0x03, DeviceName: "iPhone 16 Pro"}},
		{name: "hello", seq: 3, pkt: protocol.Hello{Flags: 1, DeviceMask: protocol.DeviceMaskWithPads(true, true, 2), AuthTag: tag, HostName: "archbox"}},
		{name: "hello_ack", seq: 4, pkt: protocol.HelloAck{Status: protocol.StatusOK, SessionActive: true, TVActive: true, DeviceName: "Madeira"}},
		{name: "ping", seq: 5, pkt: protocol.Ping{TimestampUS: 123456789}},
		{name: "pong", seq: 6, pkt: protocol.Pong{TimestampUS: 123456789}},
		{name: "key_event", seq: 7, pkt: protocol.KeyEvent{HIDUsage: 0x1A, Pressed: true, Held: []uint16{0xE0, 0x1A}}},
		{name: "mouse_motion", seq: 8, pkt: protocol.MouseMotion{DX: -14, DY: 22, WheelX: 0, WheelY: -120, Buttons: protocol.MouseButtonLeft | protocol.MouseButtonX1}},
		{name: "mouse_button", seq: 9, pkt: protocol.MouseButton{Buttons: protocol.MouseButtonRight, ChangedMask: protocol.MouseButtonRight}},
		{name: "gamepad_state", seq: 10, pkt: protocol.GamepadState{Slot: 1, Connected: true, Buttons: protocol.GamepadA | protocol.GamepadStart, LeftTrigger: 200, RightTrigger: 255, LX: -12345, LY: 32767, RX: 0, RY: -32768}},
		{name: "release_all", seq: 11, pkt: protocol.ReleaseAll{Reason: 1}},
		{name: "rumble", seq: 12, pkt: protocol.Rumble{Slot: 0, LeftMotor: 50000, RightMotor: 22000}},
		{name: "disconnect", seq: 13, pkt: protocol.Disconnect{Reason: 0}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			wire := protocol.Marshal(tc.seq, tc.pkt)
			hdr, got, err := protocol.Unmarshal(wire)
			if err != nil {
				t.Fatalf("Unmarshal returned error: %v", err)
			}
			if hdr.Version != protocol.Version || hdr.Type != tc.pkt.PacketType() || hdr.Seq != tc.seq {
				t.Fatalf("unexpected header: %+v", hdr)
			}
			if !reflect.DeepEqual(got, tc.pkt) {
				t.Fatalf("decoded mismatch:\n got:  %#v\n want: %#v", got, tc.pkt)
			}
		})
	}
}

func TestUnmarshalErrors(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		data []byte
		want error
	}{
		{name: "empty", data: nil, want: protocol.ErrShortPacket},
		{name: "bad_magic", data: []byte{'X', 'X', 1, 0, 0, 0, 0, 0}, want: protocol.ErrBadMagic},
		{name: "bad_version", data: []byte{'M', 'A', 99, 0, 0, 0, 0, 0}, want: protocol.ErrUnsupportedVersion},
		{name: "unknown_type", data: []byte{'M', 'A', 1, 0x55, 0, 0, 0, 0}, want: protocol.ErrUnknownType},
		{name: "truncated_gamepad", data: []byte{'M', 'A', 1, byte(protocol.TypeGamepadState), 0, 0, 0, 0, 0}, want: protocol.ErrTruncated},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			_, _, err := protocol.Unmarshal(tc.data)
			if !errors.Is(err, tc.want) {
				t.Fatalf("error = %v, want %v", err, tc.want)
			}
		})
	}
}

func TestAuthTagAndKeymap(t *testing.T) {
	t.Parallel()

	if zero := protocol.AuthTag(""); zero != ([8]byte{}) {
		t.Fatalf("empty PIN tag must be zeros, got %x", zero)
	}
	t1 := protocol.AuthTag("1234")
	t2 := protocol.AuthTag("1234")
	t3 := protocol.AuthTag("9999")
	if !bytes.Equal(t1[:], t2[:]) || bytes.Equal(t1[:], t3[:]) {
		t.Fatalf("unexpected AuthTag determinism/collision")
	}

	if got := protocol.LinuxEvdevToHID(17); got != 0x1A {
		t.Fatalf("KEY_W = 0x%x, want 0x1a", got)
	}
	if got := protocol.LinuxEvdevToHID(29); got != protocol.HIDLeftCtrl {
		t.Fatalf("KEY_LEFTCTRL = 0x%x, want 0x%x", got, protocol.HIDLeftCtrl)
	}
	if got := protocol.WindowsScancodeToHID(0x11, false); got != 0x1A {
		t.Fatalf("Win W = 0x%x, want 0x1a", got)
	}
	if got := protocol.WindowsScancodeToHID(0x1D, true); got != protocol.HIDRightCtrl {
		t.Fatalf("Win RCtrl = 0x%x, want 0x%x", got, protocol.HIDRightCtrl)
	}
}

func FuzzUnmarshal(f *testing.F) {
	f.Add(protocol.Marshal(1, protocol.Discover{}))
	f.Add(protocol.Marshal(2, protocol.KeyEvent{HIDUsage: 0x04, Pressed: true, Held: []uint16{0x04}}))
	f.Add(protocol.Marshal(3, protocol.GamepadState{Slot: 0, Connected: true, Buttons: protocol.GamepadA}))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, pkt, err := protocol.Unmarshal(data)
		if err != nil {
			return
		}
		// Any packet that decodes cleanly must re-encode cleanly without panicking.
		_ = protocol.Marshal(1, pkt)
	})
}
