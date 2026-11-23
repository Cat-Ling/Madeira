# Accessories Over LAN (AoL)

AoL streams low-latency raw keyboard, mouse, and XInput gamepad events over UDP (`MAOL` v1, default UDP port `37419`) from a desktop PC (`tools/aol`) directly into Madeira on iOS, while streaming XInput rumble feedback back to the PC.

## Why AoL Exists

iOS restricts USB HID access and non-MFi / raw high-polling mice and keyboards (for instance lacking raw multi-button mouse passthrough without AssistiveTouch on iPhone, blocking raw modifier/PrintScreen/F-key capture, or restricting exotic USB gamepads). Running `madeira-aol` on a Linux or Windows PC over Wi-Fi / USB-tether / Ethernet forwards raw OS events straight to Madeira's Wine/Winios input bridge and External Display TV Console Mode.

## Architecture

| Component | Path | Purpose |
|---|---|---|
| Go Wire Protocol | `tools/aol/protocol/` | `MAOL` v1 framing, SHA-256 PIN `auth_tag`, USB HID Usage <-> Linux/Win32 keymaps |
| Go Client Library | `tools/aol/client/` | Reusable `CGO_ENABLED=0` library with LAN `DISCOVER`/`ANNOUNCE` and live UDP streaming + rumble callbacks |
| Cross-Platform Capture | `tools/aol/capture/` | Linux `/dev/input/event*` `evdev` (`EVIOCGRAB` capture, rumble via `FF_RUMBLE`), Windows Raw Input (`WM_INPUT`) + XInput (`XInputGetState`/`XInputSetState`), stub fallback elsewhere |
| PC CLI | `tools/aol/cmd/madeira-aol/` | POSIX/GNU `getopt_long` binary (`--target`, `--discover`, `--pin`, `--release-combo`, `--keyboard`, `--mouse`, `--gamepad`) |
| iOS Receiver & UI | `app/Madeira/AccessoriesOverLAN.swift` | Pure-Swift `AOLProtocol` + `AOLHeldKeyReconciler` + `NWListener` UDP receiver + Settings UI + TV Console status integration |
| Input Injection | `app/Madeira/HardwareInput.swift`, `app/Madeira/GamepadInput.swift` | Low-latency injection alongside physical/touch inputs with `ConsoleOwnsInput` routing when TV Console UI is active |

## Building the PC Tool

```bash
cd tools/aol
CGO_ENABLED=0 go build ./cmd/madeira-aol
```

Cross-compile for Windows:

```bash
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build ./cmd/madeira-aol
```

See [tools/aol/README.md](../tools/aol/README.md) and [tools/aol/doc/madeira-aol.1](../tools/aol/doc/madeira-aol.1) for full flags and usage.
