// SPDX-FileCopyrightText: 2026 Cat-Ling
// SPDX-License-Identifier: GPL-3.0-or-later

package client

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"time"
)

// PairedPeer stores one paired Madeira instance's identity and 256-bit key.
type PairedPeer struct {
	DeviceID   string    `json:"deviceId"`
	DeviceName string    `json:"deviceName"`
	LastAddr   string    `json:"lastAddr"`
	KeyHex     string    `json:"keyHex"`
	PairedAt   time.Time `json:"pairedAt"`
}

// KeyStore persists the PC's ClientID and paired Madeira keys on disk.
type KeyStore struct {
	path     string
	ClientID string       `json:"clientId"`
	Peers    []PairedPeer `json:"peers"`
}

// DefaultKeyStorePath returns os.UserConfigDir()/madeira-aol/paired.json.
func DefaultKeyStorePath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "madeira-aol", "paired.json"), nil
}

// LoadKeyStore loads an existing KeyStore or initializes one with a fresh ClientID.
func LoadKeyStore(path string) (*KeyStore, error) {
	if path == "" {
		var err error
		path, err = DefaultKeyStorePath()
		if err != nil {
			return nil, err
		}
	}
	ks := &KeyStore{path: path}
	data, err := os.ReadFile(path)
	if err == nil {
		if jErr := json.Unmarshal(data, ks); jErr != nil {
			return nil, jErr
		}
		ks.path = path
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}

	if _, ok := parseHex8(ks.ClientID); !ok {
		var id [8]byte
		if _, rErr := rand.Read(id[:]); rErr != nil {
			return nil, rErr
		}
		ks.ClientID = hex.EncodeToString(id[:])
	}
	return ks, nil
}

// ClientIDBytes returns the 8-byte client identifier.
func (ks *KeyStore) ClientIDBytes() [8]byte {
	id, _ := parseHex8(ks.ClientID)
	return id
}

// Path returns the backing file path of this KeyStore.
func (ks *KeyStore) Path() string {
	return ks.path
}

// Save atomically writes the key store with 0600 permissions.
func (ks *KeyStore) Save() error {
	if err := os.MkdirAll(filepath.Dir(ks.path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(ks, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	tmp := ks.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, ks.path)
}

// Lookup finds a saved pairing key by deviceID (preferred) or last known IP/host.
func (ks *KeyStore) Lookup(deviceID [8]byte, addr string) ([32]byte, string, bool) {
	var zero [32]byte
	if ks == nil {
		return zero, "", false
	}
	devHex := hex.EncodeToString(deviceID[:])
	host := extractHost(addr)

	if deviceID != ([8]byte{}) {
		for _, p := range ks.Peers {
			if p.DeviceID == devHex {
				if key, ok := parseHex32(p.KeyHex); ok {
					return key, p.DeviceID, true
				}
			}
		}
	}
	if host != "" {
		for _, p := range ks.Peers {
			if extractHost(p.LastAddr) == host {
				if key, ok := parseHex32(p.KeyHex); ok {
					return key, p.DeviceID, true
				}
			}
		}
	}
	return zero, "", false
}

// Upsert records or updates a paired Madeira device.
func (ks *KeyStore) Upsert(deviceID [8]byte, key [32]byte, name, addr string) error {
	devHex := hex.EncodeToString(deviceID[:])
	keyHex := hex.EncodeToString(key[:])
	now := time.Now().UTC()

	for i := range ks.Peers {
		if ks.Peers[i].DeviceID == devHex || (extractHost(addr) != "" && extractHost(ks.Peers[i].LastAddr) == extractHost(addr)) {
			ks.Peers[i].DeviceID = devHex
			ks.Peers[i].DeviceName = name
			ks.Peers[i].LastAddr = addr
			ks.Peers[i].KeyHex = keyHex
			ks.Peers[i].PairedAt = now
			return ks.Save()
		}
	}
	ks.Peers = append(ks.Peers, PairedPeer{
		DeviceID:   devHex,
		DeviceName: name,
		LastAddr:   addr,
		KeyHex:     keyHex,
		PairedAt:   now,
	})
	return ks.Save()
}

// Forget removes any saved peer matching deviceIDHex or host/addr and returns true if removed.
func (ks *KeyStore) Forget(deviceIDHex, addr string) (bool, error) {
	if ks == nil {
		return false, nil
	}
	host := extractHost(addr)
	kept := ks.Peers[:0]
	removed := false
	for _, p := range ks.Peers {
		matchID := deviceIDHex != "" && p.DeviceID == deviceIDHex
		matchHost := host != "" && extractHost(p.LastAddr) == host
		if matchID || matchHost {
			removed = true
			continue
		}
		kept = append(kept, p)
	}
	ks.Peers = kept
	if !removed {
		return false, nil
	}
	return true, ks.Save()
}

func parseHex8(s string) ([8]byte, bool) {
	var out [8]byte
	b, err := hex.DecodeString(s)
	if err != nil || len(b) != 8 {
		return out, false
	}
	copy(out[:], b)
	return out, true
}

func parseHex32(s string) ([32]byte, bool) {
	var out [32]byte
	b, err := hex.DecodeString(s)
	if err != nil || len(b) != 32 {
		return out, false
	}
	copy(out[:], b)
	return out, true
}

func extractHost(addr string) string {
	if addr == "" {
		return ""
	}
	if h, _, err := net.SplitHostPort(addr); err == nil {
		return h
	}
	return addr
}
