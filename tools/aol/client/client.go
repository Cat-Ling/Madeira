// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package client

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

// Handshake and session errors returned by Dial and Client methods.
var (
	ErrRejectedPIN      = errors.New("rejected by Madeira: invalid PIN")
	ErrDisabledOnTarget = errors.New("rejected by Madeira: Accessories Over LAN is disabled")
)

// Config configures how Client connects to and authenticates with Madeira.
type Config struct {
	HostName     string
	PIN          string
	DeviceMask   uint8
	HandshakeTTL time.Duration
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

// Client streams input events over UDP to one Madeira instance and receives
// latency pings and controller rumble packets in return.
type Client struct {
	conn *net.UDPConn
	cfg  Config

	cancel context.CancelFunc
	wg     sync.WaitGroup

	seq      atomic.Uint32
	sent     atomic.Uint64
	recv     atomic.Uint64
	rttNS    atomic.Int64
	closeMu  sync.Mutex
	closed   bool
	remote   string
	ack      protocol.HelloAck
	sendMu   sync.Mutex
	scratch  []byte
	discOnce sync.Once
}

// Dial resolves addr, performs the MAOL v1 Hello handshake, and starts
// background ping and receive loops owned by the Client until Close is called
// or ctx is cancelled.
func Dial(ctx context.Context, addr string, cfg Config) (*Client, error) {
	udpAddr, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		return nil, fmt.Errorf("resolve target %q: %w", addr, err)
	}
	conn, err := net.DialUDP("udp", nil, udpAddr)
	if err != nil {
		return nil, fmt.Errorf("dial udp %s: %w", addr, err)
	}

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

	hello := protocol.Hello{
		Flags:      0,
		DeviceMask: cfg.DeviceMask,
		AuthTag:    protocol.AuthTag(cfg.PIN),
		HostName:   host,
	}

	ack, err := handshake(ctx, conn, hello, ttl)
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
	default:
		_ = conn.Close()
		return nil, fmt.Errorf("unexpected handshake status %d", ack.Status)
	}

	loopCtx, cancel := context.WithCancel(context.Background())
	c := &Client{
		conn:    conn,
		cfg:     cfg,
		cancel:  cancel,
		remote:  udpAddr.String(),
		ack:     ack,
		scratch: make([]byte, 0, 64),
	}
	c.seq.Store(1)

	c.wg.Add(2)
	go c.readLoop(loopCtx)
	go c.pingLoop(loopCtx)

	go func() {
		<-ctx.Done()
		_ = c.Close()
	}()

	return c, nil
}

func handshake(ctx context.Context, conn *net.UDPConn, hello protocol.Hello, ttl time.Duration) (protocol.HelloAck, error) {
	wire := protocol.Marshal(1, hello)
	deadline := time.Now().Add(ttl)
	buf := make([]byte, 512)

	for time.Now().Before(deadline) {
		if err := ctx.Err(); err != nil {
			return protocol.HelloAck{}, err
		}
		if _, err := conn.Write(wire); err != nil {
			return protocol.HelloAck{}, fmt.Errorf("send hello: %w", err)
		}
		_ = conn.SetReadDeadline(time.Now().Add(300 * time.Millisecond))
		n, err := conn.Read(buf)
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				continue
			}
			return protocol.HelloAck{}, fmt.Errorf("read hello ack: %w", err)
		}
		_, pkt, err := protocol.Unmarshal(buf[:n])
		if err != nil {
			continue
		}
		if ack, ok := pkt.(protocol.HelloAck); ok {
			_ = conn.SetReadDeadline(time.Time{})
			return ack, nil
		}
	}
	return protocol.HelloAck{}, fmt.Errorf("handshake timed out waiting for Madeira at %s", conn.RemoteAddr())
}

// SendKey sends a keyboard edge and current held-key snapshot.
func (c *Client) SendKey(ev protocol.KeyEvent) error {
	return c.send(ev)
}

// SendMouseMotion sends relative pointer deltas, scroll deltas, and buttons.
func (c *Client) SendMouseMotion(ev protocol.MouseMotion) error {
	return c.send(ev)
}

// SendMouseButton sends an immediate mouse button update.
func (c *Client) SendMouseButton(ev protocol.MouseButton) error {
	return c.send(ev)
}

// SendGamepad sends a controller state snapshot for one slot (0-3).
func (c *Client) SendGamepad(ev protocol.GamepadState) error {
	return c.send(ev)
}

// ReleaseAll tells Madeira to release all currently held remote inputs.
func (c *Client) ReleaseAll(reason uint8) error {
	return c.send(protocol.ReleaseAll{Reason: reason})
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
	c.closeMu.Lock()
	if c.closed {
		c.closeMu.Unlock()
		return nil
	}
	c.closed = true
	c.closeMu.Unlock()

	_ = c.send(protocol.ReleaseAll{Reason: 0})
	_ = c.send(protocol.Disconnect{Reason: 0})
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

func (c *Client) readLoop(ctx context.Context) {
	defer c.wg.Done()
	buf := make([]byte, 512)
	for {
		if ctx.Err() != nil {
			return
		}
		_ = c.conn.SetReadDeadline(time.Now().Add(250 * time.Millisecond))
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
		switch m := pkt.(type) {
		case protocol.Pong:
			nowUS := uint64(time.Now().UnixMicro())
			if nowUS >= m.TimestampUS {
				c.rttNS.Store(int64(nowUS-m.TimestampUS) * int64(time.Microsecond))
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
			return
		}
	}
}

func (c *Client) pingLoop(ctx context.Context) {
	defer c.wg.Done()
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	_ = c.send(protocol.Ping{TimestampUS: uint64(time.Now().UnixMicro())})
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			_ = c.send(protocol.Ping{TimestampUS: uint64(time.Now().UnixMicro())})
		}
	}
}
