# madeira-aol — Accessories Over LAN (AoL)

`madeira-aol` is a cross-platform pure-Go library and CLI utility that captures raw
keyboard, mouse, and XInput-compatible gamepad input from a PC (Linux `evdev` or
Windows Raw Input + XInput) and forwards it over LAN UDP (`MAOL` v1) to Madeira
on iOS/iPadOS with minimal latency, while forwarding controller rumble back to the PC.

## Layout

- `protocol/` — Binary `MAOL` v1 wire framing, PIN authentication tag, and Linux/Windows HID keymaps.
- `client/` — Reusable UDP client library (`Discover`, `Dial`, key/mouse/gamepad senders, ping RTT, rumble callback).
- `capture/` — Platform input capture (`evdev` on Linux, Raw Input + XInput on Windows).
- `cmd/madeira-aol/` — CLI server binary.

## Build & Check

```sh
CGO_ENABLED=0 go build ./cmd/madeira-aol
go test -race ./...
```

## Quick Usage

```sh
# Discover Madeira instances on the LAN
madeira-aol --discover

# Connect directly and capture input (press Ctrl+Alt+G on the PC to toggle grab)
madeira-aol --target 192.168.1.42:37419 --pin 1234
```
