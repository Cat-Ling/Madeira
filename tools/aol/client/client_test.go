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

func TestDialPairGrantCoalescingStateSyncAndPingReply(t *testing.T) {
	t.Parallel()

	srv, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen udp: %v", err)
	}
	defer srv.Close()

	var (
		mu         sync.Mutex
		mouseCount int
		totalDX    int
		gotSync    bool
		gotPongTS  uint64
		helloCount int
	)
	devID := [8]byte{0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80}
	pairKey := [32]byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
	nonce := [8]byte{9, 8, 7, 6, 5, 4, 3, 2}

	go func() {
		buf := make([]byte, 512)
		for {
			_ = srv.SetReadDeadline(time.Now().Add(2 * time.Second))
			n, addr, err := srv.ReadFrom(buf)
			if err != nil {
				return
			}
			hdr, pkt, err := protocol.Unmarshal(buf[:n])
			if err != nil {
				continue
			}
			switch m := pkt.(type) {
			case protocol.Hello:
				mu.Lock()
				helloCount++
				hc := helloCount
				mu.Unlock()
				if hc == 1 {
					if m.Flags&protocol.HelloFlagWantPair == 0 {
						return
					}
					_, _ = srv.WriteTo(protocol.Marshal(1, protocol.HelloAck{Status: protocol.StatusOK, DeviceName: "Phone"}), addr)
					_, _ = srv.WriteTo(protocol.Marshal(2, protocol.PairGrant{
						DeviceID:  devID,
						Nonce:     nonce,
						MaskedKey: protocol.MaskPairKey("1234", nonce, pairKey),
					}), addr)
					_, _ = srv.WriteTo(protocol.Marshal(3, protocol.Ping{TimestampUS: 777777}), addr)
				} else {
					want := protocol.PairedAuthTag(pairKey, m.ClientID, hdr.Seq)
					if m.AuthTag != want {
						_, _ = srv.WriteTo(protocol.Marshal(1, protocol.HelloAck{Status: protocol.StatusUnpaired}), addr)
					} else {
						_, _ = srv.WriteTo(protocol.Marshal(1, protocol.HelloAck{Status: protocol.StatusOK, DeviceName: "Phone"}), addr)
					}
				}
			case protocol.Pong:
				mu.Lock()
				gotPongTS = m.TimestampUS
				mu.Unlock()
			case protocol.MouseMotion:
				mu.Lock()
				mouseCount++
				totalDX += int(m.DX)
				mu.Unlock()
			case protocol.StateSync:
				if len(m.Held) == 1 && m.Held[0] == 0x04 {
					mu.Lock()
					gotSync = true
					mu.Unlock()
				}
			case protocol.Disconnect:
				mu.Lock()
				hc := helloCount
				mu.Unlock()
				if hc >= 2 {
					return
				}
			}
		}
	}()

	grantCh := make(chan [32]byte, 1)
	clientID := [8]byte{0xAA, 0xBB, 0xCC, 0xDD, 1, 2, 3, 4}
	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
	defer cancel()

	c, err := client.Dial(ctx, srv.LocalAddr().String(), client.Config{
		PIN:      "1234",
		ClientID: clientID,
		WantPair: true,
		OnPairGrant: func(id [8]byte, key [32]byte, _ string) {
			if id == devID {
				select {
				case grantCh <- key:
				default:
				}
			}
		},
	})
	if err != nil {
		t.Fatalf("Dial 1 failed: %v", err)
	}

	// Burst 10 mouse events in <1ms; should coalesce into fewer packets with totalDX=30.
	for range 10 {
		_ = c.SendMouseMotion(protocol.MouseMotion{DX: 3})
	}
	_ = c.SendKey(protocol.KeyEvent{HIDUsage: 0x04, Pressed: true, Held: []uint16{0x04}})

	select {
	case gotKey := <-grantCh:
		if gotKey != pairKey {
			t.Fatalf("PairGrant key mismatch")
		}
	case <-time.After(2 * time.Second):
		t.Fatalf("timed out waiting for PairGrant")
	}

	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) {
		mu.Lock()
		ok := totalDX == 30 && gotSync && gotPongTS == 777777
		mc := mouseCount
		mu.Unlock()
		if ok {
			if mc > 3 {
				t.Fatalf("expected coalesced mouse packets <= 3, got %d", mc)
			}
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	mu.Lock()
	if totalDX != 30 || !gotSync || gotPongTS != 777777 {
		t.Fatalf("state check failed: totalDX=%d gotSync=%v gotPongTS=%d", totalDX, gotSync, gotPongTS)
	}
	mu.Unlock()
	_ = c.Close()

	// Reconnect using paired key only (no PIN needed).
	c2, err := client.Dial(ctx, srv.LocalAddr().String(), client.Config{
		ClientID:     clientID,
		PairedKey:    pairKey,
		UsePairedKey: true,
	})
	if err != nil {
		t.Fatalf("Dial 2 with paired key failed: %v", err)
	}
	_ = c2.Close()
}
