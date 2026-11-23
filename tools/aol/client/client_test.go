// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package client_test

import (
	"context"
	"errors"
	"net"
	"sync"
	"testing"
	"time"

	"github.com/Cat-Ling/Madeira/tools/aol/client"
	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

func TestDialStreamAndRumble(t *testing.T) {
	t.Parallel()

	srv, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen udp: %v", err)
	}
	defer srv.Close()

	var (
		mu       sync.Mutex
		gotTypes []protocol.PacketType
	)
	done := make(chan struct{})
	go func() {
		defer close(done)
		buf := make([]byte, 512)
		for {
			_ = srv.SetReadDeadline(time.Now().Add(2 * time.Second))
			n, addr, err := srv.ReadFrom(buf)
			if err != nil {
				return
			}
			_, pkt, err := protocol.Unmarshal(buf[:n])
			if err != nil {
				continue
			}
			mu.Lock()
			gotTypes = append(gotTypes, pkt.PacketType())
			mu.Unlock()
			switch m := pkt.(type) {
			case protocol.Hello:
				status := protocol.StatusOK
				if m.AuthTag != protocol.AuthTag("1234") {
					status = protocol.StatusBadPIN
				}
				ack := protocol.Marshal(1, protocol.HelloAck{
					Status:        status,
					SessionActive: true,
					TVActive:      true,
					DeviceName:    "TestPhone",
				})
				_, _ = srv.WriteTo(ack, addr)
			case protocol.Ping:
				pong := protocol.Marshal(2, protocol.Pong{TimestampUS: m.TimestampUS})
				_, _ = srv.WriteTo(pong, addr)
				rumble := protocol.Marshal(3, protocol.Rumble{Slot: 0, LeftMotor: 40000, RightMotor: 15000})
				_, _ = srv.WriteTo(rumble, addr)
			case protocol.Disconnect:
				return
			}
		}
	}()

	rumbleCh := make(chan protocol.Rumble, 4)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	c, err := client.Dial(ctx, srv.LocalAddr().String(), client.Config{
		HostName:   "pc",
		PIN:        "1234",
		DeviceMask: protocol.DeviceMaskWithPads(true, true, 1),
		OnRumble:   func(r protocol.Rumble) { rumbleCh <- r },
	})
	if err != nil {
		t.Fatalf("Dial failed: %v", err)
	}

	if err := c.SendKey(protocol.KeyEvent{HIDUsage: 0x04, Pressed: true, Held: []uint16{0x04}}); err != nil {
		t.Fatalf("SendKey: %v", err)
	}
	if err := c.SendMouseMotion(protocol.MouseMotion{DX: 12, DY: -8, WheelY: 120, Buttons: protocol.MouseButtonLeft}); err != nil {
		t.Fatalf("SendMouseMotion: %v", err)
	}
	if err := c.SendGamepad(protocol.GamepadState{Slot: 0, Connected: true, Buttons: protocol.GamepadA, LX: 16000}); err != nil {
		t.Fatalf("SendGamepad: %v", err)
	}

	select {
	case r := <-rumbleCh:
		if r.Slot != 0 || r.LeftMotor != 40000 || r.RightMotor != 15000 {
			t.Fatalf("unexpected rumble: %+v", r)
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("timed out waiting for rumble callback")
	}

	st := c.Stats()
	if st.DeviceName != "TestPhone" || !st.TVActive || !st.SessionActive {
		t.Fatalf("unexpected stats: %+v", st)
	}

	if err := c.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	<-done
}

func TestDialBadPINRejected(t *testing.T) {
	t.Parallel()

	srv, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen udp: %v", err)
	}
	defer srv.Close()

	go func() {
		buf := make([]byte, 512)
		_ = srv.SetReadDeadline(time.Now().Add(2 * time.Second))
		n, addr, err := srv.ReadFrom(buf)
		if err != nil {
			return
		}
		_, _, _ = protocol.Unmarshal(buf[:n])
		_, _ = srv.WriteTo(protocol.Marshal(1, protocol.HelloAck{Status: protocol.StatusBadPIN, DeviceName: "Locked"}), addr)
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, err = client.Dial(ctx, srv.LocalAddr().String(), client.Config{PIN: "wrong"})
	if !errors.Is(err, client.ErrRejectedPIN) {
		t.Fatalf("err = %v, want ErrRejectedPIN", err)
	}
}
