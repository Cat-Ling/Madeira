// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package client

import (
	"context"
	"fmt"
	"net"
	"sort"
	"time"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

// Peer describes one Madeira instance that answered a LAN discovery probe.
type Peer struct {
	Addr       string `json:"addr"`
	Port       uint16 `json:"port"`
	Flags      uint8  `json:"flags"`
	DeviceName string `json:"deviceName"`
}

// Discover broadcasts a MAOL discovery packet on port and collects unique
// responding Madeira instances until timeout expires or ctx is cancelled.
func Discover(ctx context.Context, port int, timeout time.Duration) ([]Peer, error) {
	if port <= 0 {
		port = protocol.DefaultPort
	}
	if timeout <= 0 {
		timeout = 1500 * time.Millisecond
	}

	pc, err := net.ListenPacket("udp4", ":0")
	if err != nil {
		return nil, fmt.Errorf("listen udp4 discovery socket: %w", err)
	}
	defer pc.Close()

	probe := protocol.Marshal(1, protocol.Discover{})
	targets := broadcastTargets(port)
	for _, dst := range targets {
		_, _ = pc.WriteTo(probe, dst)
	}

	deadline := time.Now().Add(timeout)
	seen := make(map[string]Peer)
	buf := make([]byte, 512)

	for {
		if ctx.Err() != nil {
			break
		}
		if err := pc.SetReadDeadline(time.Now().Add(minDuration(100*time.Millisecond, time.Until(deadline)))); err != nil {
			break
		}
		n, src, err := pc.ReadFrom(buf)
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				if time.Now().After(deadline) {
					break
				}
				continue
			}
			break
		}
		_, pkt, err := protocol.Unmarshal(buf[:n])
		if err != nil {
			continue
		}
		ann, ok := pkt.(protocol.Announce)
		if !ok {
			continue
		}
		udpAddr, ok := src.(*net.UDPAddr)
		if !ok {
			continue
		}
		peerPort := ann.Port
		if peerPort == 0 {
			peerPort = uint16(port)
		}
		addr := net.JoinHostPort(udpAddr.IP.String(), fmt.Sprintf("%d", peerPort))
		seen[addr] = Peer{
			Addr:       addr,
			Port:       peerPort,
			Flags:      ann.Flags,
			DeviceName: ann.DeviceName,
		}
	}

	peers := make([]Peer, 0, len(seen))
	for _, p := range seen {
		peers = append(peers, p)
	}
	sort.Slice(peers, func(i, j int) bool { return peers[i].Addr < peers[j].Addr })
	return peers, nil
}

func broadcastTargets(port int) []*net.UDPAddr {
	seen := map[string]struct{}{}
	var out []*net.UDPAddr
	add := func(ip net.IP) {
		if ip4 := ip.To4(); ip4 != nil {
			key := ip4.String()
			if _, ok := seen[key]; !ok {
				seen[key] = struct{}{}
				out = append(out, &net.UDPAddr{IP: ip4, Port: port})
			}
		}
	}

	if ifaces, err := net.Interfaces(); err == nil {
		for _, iface := range ifaces {
			if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
				continue
			}
			addrs, err := iface.Addrs()
			if err != nil {
				continue
			}
			for _, a := range addrs {
				ipNet, ok := a.(*net.IPNet)
				if !ok {
					continue
				}
				ip4 := ipNet.IP.To4()
				mask := ipNet.Mask
				if ip4 == nil || len(mask) != 4 {
					continue
				}
				bcast := make(net.IP, 4)
				for i := range 4 {
					bcast[i] = ip4[i] | ^mask[i]
				}
				add(bcast)
			}
		}
	}
	add(net.IPv4bcast)
	return out
}

func minDuration(a, b time.Duration) time.Duration {
	if a < b {
		return a
	}
	return b
}
