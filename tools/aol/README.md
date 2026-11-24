# Madeira Accessories Over LAN (`madeira-aol`)

Pure-Go (`CGO_ENABLED=0`, zero external dependencies) PC host capture daemon,
reusable Go library, and CLI for streaming raw keyboard, mouse, and XInput
gamepad events over LAN UDP (`MAOL` v1, port `37419`) into Madeira on iOS,
while forwarding XInput rumble feedback back to the PC.

## Quick Build

```bash
CGO_ENABLED=0 go build ./cmd/madeira-aol
```

Cross-compile for Windows:

```bash
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build ./cmd/madeira-aol
```

## Usage

```bash
# Discover Madeira instances on the local network:
./madeira-aol --discover

# Initial pairing using the PIN shown in Madeira -> Settings -> Accessories Over LAN:
./madeira-aol --target <IPHONE_IP>:37419 --pin <PIN>

# Subsequent runs automatically use the saved pairing key (even if PIN changes)
# and auto-reconnect across game switches and app restarts:
./madeira-aol
```

Press **Ctrl+Alt+G** while streaming to toggle exclusive input grab on Linux
and release/re-capture all keys on Windows.

## Packages

- `github.com/Cat-Ling/Madeira/tools/aol/protocol`: wire framing, SHA-256 PIN/paired-key auth, keymaps
- `github.com/Cat-Ling/Madeira/tools/aol/client`: UDP discovery, DSCP EF QoS, 250 Hz mouse coalescing, redundant StateSync, keystore, and rumble callbacks
- `github.com/Cat-Ling/Madeira/tools/aol/capture`: Linux `evdev` + Windows Raw Input / XInput backends
- `github.com/Cat-Ling/Madeira/tools/aol/cmd/madeira-aol`: POSIX/GNU CLI with auto-reconnect supervisor
