// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/Cat-Ling/Madeira/tools/aol/capture"
	"github.com/Cat-Ling/Madeira/tools/aol/client"
	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

const (
	progName = "madeira-aol"
	version  = "1.1.0"
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
	if cfg.forget {
		return runForget(cfg)
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
		if p.DeviceID != "" {
			fmt.Printf("%s\t%s\tid=%s\n", p.Addr, p.DeviceName, p.DeviceID)
		} else {
			fmt.Printf("%s\t%s\n", p.Addr, p.DeviceName)
		}
	}
	return 0
}

func runForget(cfg cliConfig) int {
	if cfg.target == "" {
		fmt.Fprintf(os.Stderr, "%s: --forget requires a target HOST[:PORT] or device ID\n", progName)
		return 2
	}
	ks, err := client.LoadKeyStore(cfg.keyFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: key store: %v\n", progName, err)
		return 1
	}
	removed, err := ks.Forget(cfg.target, cfg.target)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: forget: %v\n", progName, err)
		return 1
	}
	if !removed {
		fmt.Fprintf(os.Stderr, "%s: no saved pairing matched %q in %s\n", progName, cfg.target, ks.Path())
		return 1
	}
	if !cfg.quiet {
		fmt.Fprintf(os.Stderr, "%s: forgot pairing for %s (%s)\n", progName, cfg.target, ks.Path())
	}
	return 0
}

func runStream(ctx context.Context, cfg cliConfig) int {
	ks, ksErr := client.LoadKeyStore(cfg.keyFile)
	if ksErr != nil {
		if cfg.keyFile != "" {
			fmt.Fprintf(os.Stderr, "%s: key store %s: %v\n", progName, cfg.keyFile, ksErr)
			return 1
		}
		if !cfg.quiet {
			fmt.Fprintf(os.Stderr, "%s: warning: pairing key persistence disabled (%v)\n", progName, ksErr)
		}
	}

	var capRef capture.Capturer
	var activeClient atomic.Pointer[client.Client]

	capOpts := capture.Options{
		Keyboard: cfg.keyboard,
		Mouse:    cfg.mouse,
		Gamepad:  cfg.gamepad,
		Grab:     cfg.grab,
		Rumble:   cfg.rumble,
		OnEvent: func(ev capture.Event) {
			cl := activeClient.Load()
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
		},
	}

	capDev, err := capture.New(capOpts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: capture: %v\n", progName, err)
		return 1
	}
	capRef = capDev
	// Do not grab desktop input until a Madeira connection is established.
	capDev.SetConnected(false)

	capCtx, cancelCap := context.WithCancel(ctx)
	defer cancelCap()

	capErrCh := make(chan error, 1)
	go func() {
		capErrCh <- capDev.Run(capCtx)
	}()

	summary := capDev.Summary()
	deviceMask := protocol.DeviceMaskWithPads(cfg.keyboard && summary.Keyboards > 0, cfg.mouse && summary.Mice > 0, uint8(summary.Gamepads))

	var lastErrMsg string
	logConnectErr := func(msg string) {
		if cfg.quiet || msg == lastErrMsg {
			return
		}
		lastErrMsg = msg
		fmt.Fprintf(os.Stderr, "%s: %s\n", progName, msg)
	}

	forcePair := cfg.forcePair
	for {
		if ctx.Err() != nil {
			cancelCap()
			<-capErrCh
			return 0
		}
		select {
		case err := <-capErrCh:
			if err != nil && ctx.Err() == nil {
				fmt.Fprintf(os.Stderr, "%s: capture runtime: %v\n", progName, err)
				return 1
			}
			return 0
		default:
		}

		targetAddr, devID, err := resolveTarget(ctx, cfg, ks)
		if err != nil {
			if ctx.Err() != nil {
				continue
			}
			if cfg.noReconnect {
				fmt.Fprintf(os.Stderr, "%s: %v\n", progName, err)
				cancelCap()
				<-capErrCh
				return 1
			}
			logConnectErr(fmt.Sprintf("%v (retrying...)", err))
			if !sleepOrDone(ctx, 750*time.Millisecond) {
				continue
			}
			continue
		}

		var clientID [8]byte
		if ks != nil {
			clientID = ks.ClientIDBytes()
		}

		var pairKey [32]byte
		var haveSaved bool
		var savedDevHex string
		if ks != nil && !forcePair {
			pairKey, savedDevHex, haveSaved = ks.Lookup(devID, targetAddr)
		}

		var pairOnce sync.Once
		onGrant := func(grantedID [8]byte, grantedKey [32]byte, devName string) {
			if ks == nil {
				return
			}
			pairOnce.Do(func() {
				if saveErr := ks.Upsert(grantedID, grantedKey, devName, targetAddr); saveErr != nil {
					if !cfg.quiet {
						fmt.Fprintf(os.Stderr, "%s: warning: could not save pairing key: %v\n", progName, saveErr)
					}
					return
				}
				if !cfg.quiet {
					label := devName
					if label == "" {
						label = targetAddr
					}
					fmt.Fprintf(os.Stderr, "%s: paired with %s (saved key to %s)\n", progName, label, ks.Path())
				}
			})
		}

		dialCfg := client.Config{
			PIN:          cfg.pin,
			ClientID:     clientID,
			PairedKey:    pairKey,
			UsePairedKey: haveSaved,
			WantPair:     ks != nil && (!haveSaved || forcePair),
			DeviceMask:   deviceMask,
			HandshakeTTL: 1200 * time.Millisecond,
			OnPairGrant:  onGrant,
			OnRumble: func(r protocol.Rumble) {
				if cfg.rumble && capRef != nil {
					_ = capRef.SetRumble(r.Slot, r.LeftMotor, r.RightMotor)
				}
			},
		}

		cl, err := client.Dial(ctx, targetAddr, dialCfg)
		if err != nil && errors.Is(err, client.ErrUnpaired) {
			if ks != nil {
				_, _ = ks.Forget(savedDevHex, targetAddr)
			}
			haveSaved = false
			if cfg.pin != "" {
				dialCfg.UsePairedKey = false
				dialCfg.PairedKey = [32]byte{}
				dialCfg.WantPair = ks != nil
				cl, err = client.Dial(ctx, targetAddr, dialCfg)
			}
		}

		if err != nil {
			if ctx.Err() != nil {
				continue
			}
			if errors.Is(err, client.ErrRejectedPIN) {
				fmt.Fprintf(os.Stderr, "%s: %v\n", progName, err)
				cancelCap()
				<-capErrCh
				return 1
			}
			if errors.Is(err, client.ErrUnpaired) {
				fmt.Fprintf(os.Stderr, "%s: Madeira no longer recognizes saved pairing; pass --pin <PIN> --pair to re-pair\n", progName)
				cancelCap()
				<-capErrCh
				return 1
			}
			if cfg.noReconnect {
				fmt.Fprintf(os.Stderr, "%s: connect %s: %v\n", progName, targetAddr, err)
				cancelCap()
				<-capErrCh
				return 1
			}
			logConnectErr(fmt.Sprintf("connect %s: %v (retrying...)", targetAddr, err))
			_ = sleepOrDone(ctx, 500*time.Millisecond)
			continue
		}

		forcePair = false
		lastErrMsg = ""
		activeClient.Store(cl)
		capDev.SetConnected(true)

		if !cfg.quiet {
			st := cl.Stats()
			curSummary := capDev.Summary()
			mode := "pin"
			if haveSaved {
				mode = "paired-key"
			}
			fmt.Fprintf(os.Stderr, "%s: connected to %s (%s) auth=%s kb=%d mouse=%d pads=%d grab=%t (Ctrl+Alt+G toggles grab)\n",
				progName, st.DeviceName, st.RemoteAddr, mode, curSummary.Keyboards, curSummary.Mice, curSummary.Gamepads, curSummary.Grabbed)
		}

		select {
		case <-ctx.Done():
			_ = cl.Close()
			activeClient.Store(nil)
			capDev.SetConnected(false)
			cancelCap()
			<-capErrCh
			return 0
		case err := <-capErrCh:
			_ = cl.Close()
			activeClient.Store(nil)
			if err != nil && ctx.Err() == nil {
				fmt.Fprintf(os.Stderr, "%s: capture runtime: %v\n", progName, err)
				return 1
			}
			return 0
		case <-cl.Done():
			activeClient.Store(nil)
			capDev.SetConnected(false)
			termErr := cl.Err()
			if cfg.noReconnect {
				if termErr != nil && !cfg.quiet {
					fmt.Fprintf(os.Stderr, "%s: %v\n", progName, termErr)
				}
				cancelCap()
				<-capErrCh
				return 0
			}
			if !cfg.quiet {
				fmt.Fprintf(os.Stderr, "%s: session paused (%v); auto-reconnecting...\n", progName, termErr)
			}
			_ = sleepOrDone(ctx, 350*time.Millisecond)
		}
	}
}

func resolveTarget(ctx context.Context, cfg cliConfig, ks *client.KeyStore) (string, [8]byte, error) {
	var zeroID [8]byte
	if cfg.target != "" {
		if _, _, err := net.SplitHostPort(cfg.target); err != nil {
			return net.JoinHostPort(cfg.target, strconv.Itoa(cfg.port)), zeroID, nil
		}
		return cfg.target, zeroID, nil
	}
	peers, err := client.Discover(ctx, cfg.port, 900*time.Millisecond)
	if err != nil {
		return "", zeroID, fmt.Errorf("discover: %w", err)
	}
	if len(peers) == 0 {
		return "", zeroID, fmt.Errorf("no Madeira instance found on UDP port %d", cfg.port)
	}
	chosen := peers[0]
	if ks != nil {
		for _, p := range peers {
			if p.DeviceID != "" {
				if idBytes, err := hex.DecodeString(p.DeviceID); err == nil && len(idBytes) == 8 {
					var id [8]byte
					copy(id[:], idBytes)
					if _, _, ok := ks.Lookup(id, p.Addr); ok {
						chosen = p
						break
					}
				}
			}
		}
	}
	if chosen.DeviceID != "" {
		if idBytes, err := hex.DecodeString(chosen.DeviceID); err == nil && len(idBytes) == 8 {
			copy(zeroID[:], idBytes)
		}
	}
	return chosen.Addr, zeroID, nil
}

func sleepOrDone(ctx context.Context, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-t.C:
		return true
	}
}

func printHelp() {
	fmt.Printf(`Usage: %s [OPTION]... [HOST[:PORT]]
Forward PC keyboard, mouse, and gamepad input over LAN to Madeira.

  -d, --discover         discover Madeira instances on the LAN and exit
  -t, --target=ADDR      connect to Madeira at HOST[:PORT]
  -p, --port=PORT        UDP port for discovery/target (default: %d)
      --pin=PIN          matching PIN when pairing or when required by Madeira
      --pair             force fresh PIN pairing and save key
      --forget           remove saved pairing key for target HOST/ID and exit
      --key-file=PATH    override paired keys JSON file path
      --no-reconnect     exit on disconnect instead of waiting to reconnect
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
Once paired with --pin, future runs auto-reconnect using the saved key even if
Madeira regenerates its PIN.
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
