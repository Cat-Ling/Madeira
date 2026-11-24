// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

//go:build windows

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
	const (
		dscpEF        = 0xB8 // DSCP EF (46) -> WMM AC_VO
		winIPTOS      = 3    // IP_TOS in Winsock2
		winIPv6TClass = 39   // IPV6_TCLASS in Winsock2
	)
	_ = raw.Control(func(fd uintptr) {
		_ = syscall.SetsockoptInt(syscall.Handle(fd), syscall.IPPROTO_IP, winIPTOS, dscpEF)
		_ = syscall.SetsockoptInt(syscall.Handle(fd), syscall.IPPROTO_IPV6, winIPv6TClass, dscpEF)
	})
}
