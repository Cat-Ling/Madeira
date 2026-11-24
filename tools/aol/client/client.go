// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package client

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"slices"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

// Handshake and session errors returned by Dial and Client methods.
var (
	ErrRejectedPIN      = errors.New("rejected by Madeira: invalid PIN")
	ErrDisabledOnTarget = errors.New("rejected by Madeira: Accessories Over LAN is disabled")
	ErrUnpaired         = errors.New("rejected by Madeira: unpaired client key")
	ErrTimedOut         = errors.New("connection timed out waiting for Madeira")
)

// DisconnectError reports a remote disconnect packet reason.
type DisconnectError struct {
	Reason uint8
}

func (e DisconnectError) Error() string {
	return fmt.Sprintf("remote disconnected (reason=%d)", e.Reason)
}

// Config configures how Client connects to and authenticates with Madeira.
type Config struct {
	HostName     string
	PIN          string
	ClientID     [8]byte
	PairedKey    [32]byte
	UsePairedKey bool
	WantPair     bool
	DeviceMask   uint8
	HandshakeTTL time.Duration
	OnPairGrant  func(deviceID [8]byte, key [32]byte, deviceName string)
	OnRumble     func(protocol.Rumble)
	OnDisconnect func(reason uint8)
}

// Stats reports live transport counters for an active Client session.
type Stats struct {
	RemoteAddr    string
	DeviceName    string
	SessionActive bool
	TVActive      bool
	RTT           time.Duration
	PacketsSent   uint64
	PacketsRecv   uint64
}

// Client streams input events over UDP to one Madeira instance with mouse
// coalescing, redundant state synchronization, QoS tagging, and rumble receive.
type Client struct {
	conn *net.UDPConn
	cfg  Config

	cancel context.CancelFunc
	wg     sync.WaitGroup

	seq        atomic.Uint32
	sent       atomic.Uint64
	recv       atomic.Uint64
	rttNS      atomic.Int64
	lastRecvNS atomic.Int64

	closeMu sync.Mutex
	closed  bool
	done    chan struct{}
	doneMu  sync.Mutex
	termErr error

	remote string
	ack    protocol.HelloAck

	sendMu  sync.Mutex
	scratch []byte

	txMu             sync.Mutex
	pendingMouse     bool
	mouseDX, mouseDY int32
	mouseWX, mouseWY int32
	mouseBtns        uint8
	heldKeys         []uint16
	heldBtns         uint8
	syncEchoes       int
	nextSyncAt       time.Time
	lastSyncSentAt   time.Time
	syncClearUntil   time.Time
	pads             [4]protocol.GamepadState
	padDirty         [4]bool
	lastPadSent      [4]time.Time

	discOnce sync.Once
}

// Dial resolves addr, performs the MAOL v1 Hello handshake, and starts
// background tx, ping, and receive loops owned by the Client until Close is
// called, ctx is cancelled, or the remote session drops.
func Dial(ctx context.Context, addr string, cfg Config) (*Client, error) {
	udpAddr, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		return nil, fmt.Errorf("resolve target %q: %w", addr, err)
	}
	conn, err := net.DialUDP("udp", nil, udpAddr)
	if err != nil {
		return nil, fmt.Errorf("dial udp %s: %w", addr, err)
	}
	tuneUDPSocket(conn)

	host := cfg.HostName
	if host == "" {
		if h, err := os.Hostname(); err == nil && h != "" {
			host = h
		} else {
			host = "madeira-aol"
		}
	}
	ttl := cfg.HandshakeTTL
	if ttl <= 0 {
		ttl = 3 * time.Second
	}

	var flags uint8
	if cfg.WantPair {
		flags |= protocol.HelloFlagWantPair
	}
	if cfg.UsePairedKey {
		flags |= protocol.HelloFlagPairedKey
	}
	if cfg.ClientID != ([8]byte{}) {
		flags |= protocol.HelloFlagHasClientID
	}

	hello := protocol.Hello{
		Flags:      flags,
		DeviceMask: cfg.DeviceMask,
		HostName:   host,
		ClientID:   cfg.ClientID,
	}

	ack, err := handshake(ctx, conn, hello, cfg, ttl)
	if err != nil {
		_ = conn.Close()
		return nil, err
	}
	switch ack.Status {
	case protocol.StatusOK:
	case protocol.StatusBadPIN:
		_ = conn.Close()
		return nil, ErrRejectedPIN
	case protocol.StatusDisabled:
		_ = conn.Close()
		return nil, ErrDisabledOnTarget
	case protocol.StatusUnpaired:
		_ = conn.Close()
		return nil, ErrUnpaired
	default:
		_ = conn.Close()
		return nil, fmt.Errorf("unexpected handshake status %d", ack.Status)
	}

	loopCtx, cancel := context.WithCancel(context.Background())
	now := time.Now()
	c := &Client{
		conn:    conn,
		cfg:     cfg,
		cancel:  cancel,
		done:    make(chan struct{}),
		remote:  udpAddr.String(),
		ack:     ack,
		scratch: make([]byte, 0, 96),
	}
	c.seq.Store(4)
	c.lastRecvNS.Store(now.UnixNano())

	c.wg.Add(3)
	go c.readLoop(loopCtx)
	go c.txLoop(loopCtx)
	go c.pingLoop(loopCtx)

	go func() {
		<-ctx.Done()
		_ = c.Close()
	}()

	return c, nil
}

func handshake(ctx context.Context, conn *net.UDPConn, hello protocol.Hello, cfg Config, ttl time.Duration) (protocol.HelloAck, error) {
	deadline := time.Now().Add(ttl)
	buf := make([]byte, 512)
	var seq uint32 = 1

	for time.Now().Before(deadline) {
		if err := ctx.Err(); err != nil {
			return protocol.HelloAck{}, err
		}
		h := hello
		if cfg.UsePairedKey {
			h.AuthTag = protocol.PairedAuthTag(cfg.PairedKey, cfg.ClientID, seq)
		} else {
			h.AuthTag = protocol.AuthTag(cfg.PIN)
		}
		wire := protocol.Marshal(seq, h)
		seq++

		if _, err := conn.Write(wire); err != nil {
			return protocol.HelloAck{}, fmt.Errorf("send hello: %w", err)
		}
		_ = conn.SetReadDeadline(time.Now().Add(250 * time.Millisecond))
		for time.Now().Before(deadline) {
			n, err := conn.Read(buf)
			if err != nil {
				if ne, ok := err.(net.Error); ok && ne.Timeout() {
					break
				}
				return protocol.HelloAck{}, fmt.Errorf("read hello ack: %w", err)
			}
			_, pkt, err := protocol.Unmarshal(buf[:n])
			if err != nil {
				continue
			}
			switch m := pkt.(type) {
			case protocol.HelloAck:
				_ = conn.SetReadDeadline(time.Time{})
				return m, nil
			case protocol.PairGrant:
				if cfg.OnPairGrant != nil {
					key := protocol.MaskPairKey(cfg.PIN, m.Nonce, m.MaskedKey)
					cfg.OnPairGrant(m.DeviceID, key, "")
				}
			}
		}
	}
	return protocol.HelloAck{}, fmt.Errorf("handshake timed out waiting for Madeira at %s", conn.RemoteAddr())
}

// Done returns a channel that closes when the Client shuts down or the remote
// session disconnects/times out.
func (c *Client) Done() <-chan struct{} {
	return c.done
}

// Err returns the terminal session error after Done closes (nil on normal Close).
func (c *Client) Err() error {
	c.doneMu.Lock()
	defer c.doneMu.Unlock()
	return c.termErr
}

// SendKey sends a keyboard edge immediately, flushes any queued mouse delta, and
// schedules short StateSync redundancy so lost packets never stick keys.
func (c *Client) SendKey(ev protocol.KeyEvent) error {
	now := time.Now()
	c.txMu.Lock()
	motion, hasMotion := c.takePendingMouseLocked()
	c.heldKeys = cloneCappedHeld(ev.Held)
	c.syncEchoes = 2
	c.nextSyncAt = now.Add(10 * time.Millisecond)
	if len(c.heldKeys) == 0 && c.heldBtns == 0 {
		c.syncClearUntil = now.Add(120 * time.Millisecond)
	}
	c.txMu.Unlock()

	if hasMotion {
		_ = c.send(motion)
	}
	return c.send(ev)
}

// SendMouseMotion queues relative pointer/wheel deltas for 250 Hz coalesced transmission.
func (c *Client) SendMouseMotion(ev protocol.MouseMotion) error {
	c.txMu.Lock()
	c.mouseDX += int32(ev.DX)
	c.mouseDY += int32(ev.DY)
	c.mouseWX += int32(ev.WheelX)
	c.mouseWY += int32(ev.WheelY)
	c.mouseBtns = ev.Buttons
	c.pendingMouse = true
	c.txMu.Unlock()
	return nil
}

// SendMouseButton sends a mouse button edge immediately, flushes any queued mouse
// delta beforehand, and schedules redundant StateSync echoes.
func (c *Client) SendMouseButton(ev protocol.MouseButton) error {
	now := time.Now()
	c.txMu.Lock()
	motion, hasMotion := c.takePendingMouseLocked()
	c.mouseBtns = ev.Buttons
	c.heldBtns = ev.Buttons
	c.syncEchoes = 2
	c.nextSyncAt = now.Add(10 * time.Millisecond)
	if len(c.heldKeys) == 0 && c.heldBtns == 0 {
		c.syncClearUntil = now.Add(120 * time.Millisecond)
	}
	c.txMu.Unlock()

	if hasMotion {
		_ = c.send(motion)
	}
	return c.send(ev)
}

// SendGamepad forwards gamepad button/connection transitions immediately and
// paces analog-only axis changes at up to 250 Hz with periodic keepalives.
func (c *Client) SendGamepad(ev protocol.GamepadState) error {
	if ev.Slot >= 4 {
		return nil
	}
	now := time.Now()
	c.txMu.Lock()
	prev := c.pads[ev.Slot]
	immediate := prev.Connected != ev.Connected || prev.Buttons != ev.Buttons
	c.pads[ev.Slot] = ev
	if immediate {
		c.padDirty[ev.Slot] = false
		c.lastPadSent[ev.Slot] = now
		c.txMu.Unlock()
		return c.send(ev)
	}
	c.padDirty[ev.Slot] = true
	c.txMu.Unlock()
	return nil
}

// ReleaseAll tells Madeira to release all currently held remote inputs.
func (c *Client) ReleaseAll(reason uint8) error {
	c.txMu.Lock()
	c.pendingMouse = false
	c.mouseDX, c.mouseDY, c.mouseWX, c.mouseWY = 0, 0, 0, 0
	c.mouseBtns = 0
	c.heldBtns = 0
	c.heldKeys = nil
	c.syncEchoes = 2
	c.nextSyncAt = time.Now().Add(10 * time.Millisecond)
	c.syncClearUntil = time.Now().Add(120 * time.Millisecond)
	c.txMu.Unlock()
	if err := c.send(protocol.ReleaseAll{Reason: reason}); err != nil {
		return err
	}
	return c.send(protocol.StateSync{})
}

// Stats returns a snapshot of session state and transport counters.
func (c *Client) Stats() Stats {
	return Stats{
		RemoteAddr:    c.remote,
		DeviceName:    c.ack.DeviceName,
		SessionActive: c.ack.SessionActive,
		TVActive:      c.ack.TVActive,
		RTT:           time.Duration(c.rttNS.Load()),
		PacketsSent:   c.sent.Load(),
		PacketsRecv:   c.recv.Load(),
	}
}

// Close releases all remote inputs, notifies Madeira, and waits for background
// goroutines to exit before closing the UDP socket.
func (c *Client) Close() error {
	return c.closeWithErr(nil, true)
}

func (c *Client) closeWithErr(termErr error, sendBye bool) error {
	c.closeMu.Lock()
	if c.closed {
		c.closeMu.Unlock()
		return nil
	}
	c.closed = true
	c.closeMu.Unlock()

	c.doneMu.Lock()
	if c.termErr == nil && termErr != nil {
		c.termErr = termErr
	}
	close(c.done)
	c.doneMu.Unlock()

	if sendBye {
		_ = c.send(protocol.ReleaseAll{Reason: 0})
		_ = c.send(protocol.StateSync{})
		_ = c.send(protocol.Disconnect{Reason: protocol.ReasonNormal})
	}
	c.cancel()
	err := c.conn.Close()
	c.wg.Wait()
	return err
}

func (c *Client) send(pkt protocol.Packet) error {
	seq := c.seq.Add(1)
	c.sendMu.Lock()
	c.scratch = protocol.AppendMarshal(c.scratch[:0], seq, pkt)
	_, err := c.conn.Write(c.scratch)
	c.sendMu.Unlock()
	if err != nil {
		return fmt.Errorf("write %T: %w", pkt, err)
	}
	c.sent.Add(1)
	return nil
}

func (c *Client) txLoop(ctx context.Context) {
	defer c.wg.Done()
	ticker := time.NewTicker(4 * time.Millisecond) // 250 Hz coalescing & sync tick
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			var (
				motion    protocol.MouseMotion
				hasMotion bool
				syncPkt   protocol.StateSync
				hasSync   bool
				padPkts   [4]protocol.GamepadState
				padSend   [4]bool
			)

			c.txMu.Lock()
			if c.pendingMouse {
				motion, hasMotion = c.takePendingMouseLocked()
			}
			for slot := range 4 {
				if c.padDirty[slot] || (c.pads[slot].Connected && now.Sub(c.lastPadSent[slot]) >= 50*time.Millisecond) {
					padPkts[slot] = c.pads[slot]
					padSend[slot] = true
					c.padDirty[slot] = false
					c.lastPadSent[slot] = now
				}
			}

			nonEmpty := len(c.heldKeys) > 0 || c.heldBtns != 0
			shouldEcho := c.syncEchoes > 0 && !now.Before(c.nextSyncAt)
			shouldPeriodic := (nonEmpty || now.Before(c.syncClearUntil)) && now.Sub(c.lastSyncSentAt) >= 35*time.Millisecond
			if shouldEcho || shouldPeriodic {
				hasSync = true
				syncPkt = protocol.StateSync{
					Buttons: c.heldBtns,
					Held:    slices.Clone(c.heldKeys),
				}
				c.lastSyncSentAt = now
				if shouldEcho {
					c.syncEchoes--
					if c.syncEchoes > 0 {
						c.nextSyncAt = now.Add(15 * time.Millisecond)
					}
				}
			}
			c.txMu.Unlock()

			if hasMotion {
				_ = c.send(motion)
			}
			for slot := range 4 {
				if padSend[slot] {
					_ = c.send(padPkts[slot])
				}
			}
			if hasSync {
				_ = c.send(syncPkt)
			}
		}
	}
}

func (c *Client) readLoop(ctx context.Context) {
	defer c.wg.Done()
	buf := make([]byte, 512)
	for {
		if ctx.Err() != nil {
			return
		}
		_ = c.conn.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
		n, err := c.conn.Read(buf)
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				continue
			}
			return
		}
		_, pkt, err := protocol.Unmarshal(buf[:n])
		if err != nil {
			continue
		}
		c.recv.Add(1)
		c.lastRecvNS.Store(time.Now().UnixNano())

		switch m := pkt.(type) {
		case protocol.Ping:
			_ = c.send(protocol.Pong{TimestampUS: m.TimestampUS})
		case protocol.Pong:
			nowUS := uint64(time.Now().UnixMicro())
			if nowUS >= m.TimestampUS {
				c.rttNS.Store(int64(nowUS-m.TimestampUS) * int64(time.Microsecond))
			}
		case protocol.PairGrant:
			if c.cfg.OnPairGrant != nil {
				key := protocol.MaskPairKey(c.cfg.PIN, m.Nonce, m.MaskedKey)
				c.cfg.OnPairGrant(m.DeviceID, key, c.ack.DeviceName)
			}
		case protocol.Rumble:
			if c.cfg.OnRumble != nil {
				c.cfg.OnRumble(m)
			}
		case protocol.Disconnect:
			c.discOnce.Do(func() {
				if c.cfg.OnDisconnect != nil {
					c.cfg.OnDisconnect(m.Reason)
				}
			})
			go func(reason uint8) {
				_ = c.closeWithErr(DisconnectError{Reason: reason}, false)
			}(m.Reason)
			return
		}
	}
}

func (c *Client) pingLoop(ctx context.Context) {
	defer c.wg.Done()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()

	_ = c.send(protocol.Ping{TimestampUS: uint64(time.Now().UnixMicro())})
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-ticker.C:
			last := time.Unix(0, c.lastRecvNS.Load())
			if now.Sub(last) > 1500*time.Millisecond {
				c.discOnce.Do(func() {
					if c.cfg.OnDisconnect != nil {
						c.cfg.OnDisconnect(protocol.ReasonTimeout)
					}
				})
				go func() {
					_ = c.closeWithErr(ErrTimedOut, false)
				}()
				return
			}
			_ = c.send(protocol.Ping{TimestampUS: uint64(now.UnixMicro())})
		}
	}
}

func (c *Client) takePendingMouseLocked() (protocol.MouseMotion, bool) {
	if !c.pendingMouse {
		return protocol.MouseMotion{}, false
	}
	c.pendingMouse = false
	m := protocol.MouseMotion{
		DX:      clampDelta16(c.mouseDX),
		DY:      clampDelta16(c.mouseDY),
		WheelX:  clampDelta16(c.mouseWX),
		WheelY:  clampDelta16(c.mouseWY),
		Buttons: c.mouseBtns,
	}
	c.mouseDX, c.mouseDY, c.mouseWX, c.mouseWY = 0, 0, 0, 0
	return m, true
}

func clampDelta16(v int32) int16 {
	if v > 32767 {
		return 32767
	}
	if v < -32768 {
		return -32768
	}
	return int16(v)
}

func cloneCappedHeld(in []uint16) []uint16 {
	if len(in) == 0 {
		return nil
	}
	if len(in) > protocol.MaxHeldKeys {
		in = in[:protocol.MaxHeldKeys]
	}
	return slices.Clone(in)
}
