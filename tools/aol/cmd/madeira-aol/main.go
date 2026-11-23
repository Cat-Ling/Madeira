// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/Cat-Ling/Madeira/tools/aol/capture"
	"github.com/Cat-Ling/Madeira/tools/aol/client"
	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

const (
	progName = "madeira-aol"
	version  = "1.0.0"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(argv []string) int {
	cfg, err := parseArgs(argv)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: %v\nTry '%s --help' for more information.\n", progName, err, progName)
		return 2
	}
	if cfg.showHelp {
		printHelp()
		return 0
	}
	if cfg.showVer {
		printVersion()
		return 0
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if cfg.discover {
		return runDiscover(ctx, cfg)
	}
	return runStream(ctx, cfg)
}

func runDiscover(ctx context.Context, cfg cliConfig) int {
	peers, err := client.Discover(ctx, cfg.port, 1500*time.Millisecond)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: discover: %v\n", progName, err)
		return 1
	}
	if cfg.jsonOut {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(peers); err != nil {
			fmt.Fprintf(os.Stderr, "%s: encode json: %v\n", progName, err)
			return 1
		}
		return 0
	}
	for _, p := range peers {
		fmt.Printf("%s\t%s\n", p.Addr, p.DeviceName)
	}
	return 0
}

func runStream(ctx context.Context, cfg cliConfig) int {
	target := cfg.target
	if target == "" {
		peers, err := client.Discover(ctx, cfg.port, 1500*time.Millisecond)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: discover: %v\n", progName, err)
			return 1
		}
		if len(peers) == 0 {
			fmt.Fprintf(os.Stderr, "%s: no Madeira instance found on UDP port %d (pass --target HOST[:PORT])\n", progName, cfg.port)
			return 1
		}
		target = peers[0].Addr
	} else if _, _, err := net.SplitHostPort(target); err != nil {
		target = net.JoinHostPort(target, strconv.Itoa(cfg.port))
	}

	var capRef capture.Capturer
	capOpts := capture.Options{
		Keyboard: cfg.keyboard,
		Mouse:    cfg.mouse,
		Gamepad:  cfg.gamepad,
		Grab:     cfg.grab,
		Rumble:   cfg.rumble,
	}

	var cl *client.Client
	capOpts.OnEvent = func(ev capture.Event) {
		if cl == nil {
			return
		}
		switch ev.Kind {
		case capture.EventKey:
			_ = cl.SendKey(ev.Key)
		case capture.EventMouseMotion:
			_ = cl.SendMouseMotion(ev.Mouse)
		case capture.EventMouseButton:
			_ = cl.SendMouseButton(ev.Buttons)
		case capture.EventGamepad:
			_ = cl.SendGamepad(ev.Gamepad)
		case capture.EventCaptureToggled:
			_ = cl.ReleaseAll(1)
			if !cfg.quiet {
				state := "released"
				if ev.Grabbed {
					state = "grabbed"
				}
				fmt.Fprintf(os.Stderr, "%s: capture %s (Ctrl+Alt+G)\n", progName, state)
			}
		}
	}

	capDev, err := capture.New(capOpts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: capture: %v\n", progName, err)
		return 1
	}
	capRef = capDev
	summary := capDev.Summary()

	cl, err = client.Dial(ctx, target, client.Config{
		PIN:        cfg.pin,
		DeviceMask: protocol.DeviceMaskWithPads(cfg.keyboard && summary.Keyboards > 0, cfg.mouse && summary.Mice > 0, uint8(summary.Gamepads)),
		OnRumble: func(r protocol.Rumble) {
			if cfg.rumble && capRef != nil {
				_ = capRef.SetRumble(r.Slot, r.LeftMotor, r.RightMotor)
			}
		},
		OnDisconnect: func(reason uint8) {
			if !cfg.quiet {
				fmt.Fprintf(os.Stderr, "%s: remote closed session (reason=%d)\n", progName, reason)
			}
		},
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: connect %s: %v\n", progName, target, err)
		return 1
	}
	defer cl.Close()

	if !cfg.quiet {
		st := cl.Stats()
		fmt.Fprintf(os.Stderr, "%s: connected to %s (%s) kb=%d mouse=%d pads=%d grab=%t (Ctrl+Alt+G toggles grab)\n",
			progName, st.DeviceName, st.RemoteAddr, summary.Keyboards, summary.Mice, summary.Gamepads, summary.Grabbed)
	}

	if err := capDev.Run(ctx); err != nil && ctx.Err() == nil {
		fmt.Fprintf(os.Stderr, "%s: runtime: %v\n", progName, err)
		return 1
	}
	return 0
}

func printHelp() {
	fmt.Printf(`Usage: %s [OPTION]... [HOST[:PORT]]
Forward PC keyboard, mouse, and gamepad input over LAN to Madeira.

  -d, --discover         discover Madeira instances on the LAN and exit
  -t, --target=ADDR      connect to Madeira at HOST[:PORT]
  -p, --port=PORT        UDP port for discovery/target (default: %d)
      --pin=PIN          matching PIN when required by Madeira
      --no-keyboard      disable keyboard forwarding
      --no-mouse         disable mouse motion, button, and wheel forwarding
      --no-gamepad       disable gamepad and rumble forwarding
      --no-grab          do not exclusively grab keyboard and mouse devices
      --no-rumble        ignore controller rumble feedback from Madeira
      --json             emit discovery output as JSON
      --color=WHEN       colorize output: auto, always, never
      --no-color         disable colored output
  -q, --quiet            suppress informational diagnostics
  -v, --verbose          enable verbose diagnostics
  -h, --help             display this help and exit
  -V, --version          output version information and exit

Press Ctrl+Alt+G during streaming to toggle exclusive input capture.
`, progName, protocol.DefaultPort)
}

func printVersion() {
	fmt.Printf(`%s %s
Copyright (C) 2026 Cat-Ling
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
`, progName, version)
}
