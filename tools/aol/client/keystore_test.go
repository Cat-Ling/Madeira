// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package client_test

import (
	"path/filepath"
	"testing"

	"github.com/Cat-Ling/Madeira/tools/aol/client"
)

func TestKeyStoreRoundTrip(t *testing.T) {
	t.Parallel()

	p := filepath.Join(t.TempDir(), "paired.json")
	ks, err := client.LoadKeyStore(p)
	if err != nil {
		t.Fatalf("LoadKeyStore: %v", err)
	}
	if ks.ClientIDBytes() == ([8]byte{}) {
		t.Fatalf("expected non-zero generated ClientID")
	}

	dev := [8]byte{1, 2, 3, 4, 5, 6, 7, 8}
	var key [32]byte
	for i := range key {
		key[i] = byte(i + 10)
	}
	if err := ks.Upsert(dev, key, "iPhone 16 Pro", "192.168.1.50:37419"); err != nil {
		t.Fatalf("Upsert: %v", err)
	}

	reloaded, err := client.LoadKeyStore(p)
	if err != nil {
		t.Fatalf("reload LoadKeyStore: %v", err)
	}
	if reloaded.ClientID != ks.ClientID {
		t.Fatalf("ClientID mismatch: got %q want %q", reloaded.ClientID, ks.ClientID)
	}
	gotKey, gotID, ok := reloaded.Lookup(dev, "10.0.0.99:37419")
	if !ok || gotKey != key || gotID == "" {
		t.Fatalf("Lookup by deviceID failed: ok=%v id=%q", ok, gotID)
	}
	gotKey, _, ok = reloaded.Lookup([8]byte{}, "192.168.1.50:37419")
	if !ok || gotKey != key {
		t.Fatalf("Lookup by IP failed: ok=%v", ok)
	}
	removed, err := reloaded.Forget(gotID, "")
	if err != nil || !removed {
		t.Fatalf("Forget: removed=%v err=%v", removed, err)
	}
	if _, _, ok := reloaded.Lookup(dev, "192.168.1.50:37419"); ok {
		t.Fatalf("expected forgotten peer to disappear")
	}
}
