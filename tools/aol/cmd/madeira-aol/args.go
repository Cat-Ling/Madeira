// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package main

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

type colorWhen uint8

const (
	colorAuto colorWhen = iota
	colorAlways
	colorNever
)

type cliConfig struct {
	discover    bool
	target      string
	port        int
	pin         string
	keyFile     string
	forcePair   bool
	forget      bool
	noReconnect bool
	keyboard    bool
	mouse       bool
	gamepad     bool
	grab        bool
	rumble      bool
	jsonOut     bool
	quiet       bool
	verbose     bool
	color       colorWhen
	showHelp    bool
	showVer     bool
}

func defaultConfig() cliConfig {
	return cliConfig{
		port:     protocol.DefaultPort,
		keyboard: true,
		mouse:    true,
		gamepad:  true,
		grab:     true,
		rumble:   true,
	}
}

func parseArgs(args []string) (cliConfig, error) {
	cfg := defaultConfig()
	posixStrict := os.Getenv("POSIXLY_CORRECT") != ""
	var positional []string

	i := 0
	for i < len(args) {
		a := args[i]
		if a == "--" {
			positional = append(positional, args[i+1:]...)
			break
		}
		if len(a) < 2 || a[0] != '-' {
			positional = append(positional, a)
			i++
			if posixStrict {
				positional = append(positional, args[i:]...)
				break
			}
			continue
		}

		if strings.HasPrefix(a, "--") {
			name, val, hasVal := strings.Cut(a[2:], "=")
			needVal := func() (string, error) {
				if hasVal {
					return val, nil
				}
				if i+1 >= len(args) {
					return "", fmt.Errorf("option '--%s' requires an argument", name)
				}
				i++
				return args[i], nil
			}
			noVal := func() error {
				if hasVal {
					return fmt.Errorf("option '--%s' does not allow an argument", name)
				}
				return nil
			}

			switch name {
			case "help":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.showHelp = true
			case "version":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.showVer = true
			case "discover":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.discover = true
			case "target":
				v, err := needVal()
				if err != nil {
					return cfg, err
				}
				cfg.target = v
			case "port":
				v, err := needVal()
				if err != nil {
					return cfg, err
				}
				p, err := parsePort(v)
				if err != nil {
					return cfg, err
				}
				cfg.port = p
			case "pin":
				v, err := needVal()
				if err != nil {
					return cfg, err
				}
				cfg.pin = v
			case "key-file":
				v, err := needVal()
				if err != nil {
					return cfg, err
				}
				cfg.keyFile = v
			case "pair":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.forcePair = true
			case "forget":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.forget = true
			case "no-reconnect":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.noReconnect = true
			case "no-keyboard":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.keyboard = false
			case "no-mouse":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.mouse = false
			case "no-gamepad":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.gamepad = false
			case "no-grab":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.grab = false
			case "no-rumble":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.rumble = false
			case "json":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.jsonOut = true
			case "quiet":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.quiet = true
			case "verbose":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.verbose = true
			case "no-color":
				if err := noVal(); err != nil {
					return cfg, err
				}
				cfg.color = colorNever
			case "color":
				v, err := needVal()
				if err != nil {
					return cfg, err
				}
				switch v {
				case "auto":
					cfg.color = colorAuto
				case "always":
					cfg.color = colorAlways
				case "never":
					cfg.color = colorNever
				default:
					return cfg, fmt.Errorf("invalid argument %q for '--color'", v)
				}
			default:
				return cfg, fmt.Errorf("unrecognized option '--%s'", name)
			}
			i++
			continue
		}

		// Short options (supporting clustering such as -vq or -t192.168.1.2).
		shorts := a[1:]
		for j := 0; j < len(shorts); j++ {
			ch := shorts[j]
			takeVal := func() (string, error) {
				if j+1 < len(shorts) {
					v := shorts[j+1:]
					j = len(shorts)
					return v, nil
				}
				if i+1 >= len(args) {
					return "", fmt.Errorf("option requires an argument -- '%c'", ch)
				}
				i++
				return args[i], nil
			}

			switch ch {
			case 'h':
				cfg.showHelp = true
			case 'V':
				cfg.showVer = true
			case 'd':
				cfg.discover = true
			case 'q':
				cfg.quiet = true
			case 'v':
				cfg.verbose = true
			case 't':
				v, err := takeVal()
				if err != nil {
					return cfg, err
				}
				cfg.target = v
			case 'p':
				v, err := takeVal()
				if err != nil {
					return cfg, err
				}
				p, err := parsePort(v)
				if err != nil {
					return cfg, err
				}
				cfg.port = p
			default:
				return cfg, fmt.Errorf("invalid option -- '%c'", ch)
			}
		}
		i++
	}

	if len(positional) > 1 {
		return cfg, fmt.Errorf("unexpected extra operand %q", positional[1])
	}
	if len(positional) == 1 {
		if cfg.target != "" {
			return cfg, fmt.Errorf("cannot combine --target with positional target %q", positional[0])
		}
		cfg.target = positional[0]
	}
	return cfg, nil
}

func parsePort(s string) (int, error) {
	p, err := strconv.Atoi(s)
	if err != nil || p < 1 || p > 65535 {
		return 0, fmt.Errorf("invalid UDP port %q (must be 1-65535)", s)
	}
	return p, nil
}
