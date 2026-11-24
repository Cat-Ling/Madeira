// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

//go:build !windows

package client

import (
	"net"
	"syscall"
)

func tuneUDPSocket(conn *net.UDPConn) {
	if conn == nil {
		return
	}
	_ = conn.SetReadBuffer(256 * 1024)
	_ = conn.SetWriteBuffer(256 * 1024)
	raw, err := conn.SyscallConn()
	if err != nil {
		return
	}
	const dscpEF = 0xB8 // DSCP EF (46) -> WMM AC_VO
	_ = raw.Control(func(fd uintptr) {
		_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IP, syscall.IP_TOS, dscpEF)
		_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IPV6, syscall.IPV6_TCLASS, dscpEF)
	})
}
