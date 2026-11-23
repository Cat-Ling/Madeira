// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package main

import "testing"

func TestParseArgs(t *testing.T) {
	t.Parallel()

	t.Run("clustered_shorts_and_target", func(t *testing.T) {
		t.Parallel()
		cfg, err := parseArgs([]string{"-vq", "-p37420", "--pin=1234", "192.168.1.25"})
		if err != nil {
			t.Fatalf("parseArgs error: %v", err)
		}
		if !cfg.verbose || !cfg.quiet || cfg.port != 37420 || cfg.pin != "1234" || cfg.target != "192.168.1.25" {
			t.Fatalf("unexpected cfg: %+v", cfg)
		}
	})

	t.Run("option_permutation_unless_posixly_correct", func(t *testing.T) {
		cfg, err := parseArgs([]string{"10.0.0.5", "--no-grab", "--discover"})
		if err != nil {
			t.Fatalf("parseArgs error: %v", err)
		}
		if !cfg.discover || cfg.grab || cfg.target != "10.0.0.5" {
			t.Fatalf("unexpected cfg: %+v", cfg)
		}
	})

	t.Run("invalid_port", func(t *testing.T) {
		t.Parallel()
		if _, err := parseArgs([]string{"--port", "99999"}); err == nil {
			t.Fatalf("expected invalid port error")
		}
	})
}
