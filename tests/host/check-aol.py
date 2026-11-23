#!/usr/bin/env python3
"""Host regression tests for Accessories Over LAN (AoL):
1. Compiles and runs pure-Swift MAOL v1 protocol + key reconciler from AccessoriesOverLAN.swift.
2. Verifies binary byte-for-byte interoperability between Go (tools/aol/protocol) and Swift (AOLProtocol).
3. Verifies static wiring across Madeira iOS files and Info.plist / pbxproj.
"""

import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def swift_pure_source() -> str:
    path = os.path.join(ROOT, "app", "Madeira", "AccessoriesOverLAN.swift")
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()
    marker = "#if canImport(UIKit)"
    idx = src.find(marker)
    assert idx > 0, f"{marker} not found in AccessoriesOverLAN.swift"
    return src[:idx]


SWIFT_TEST_HARNESS = r'''
func check(_ cond: @autoclosure () -> Bool, _ msg: String) {
    if !cond() {
        fputs("FAIL: \(msg)\n", stderr)
        exit(1)
    }
}

let tag = AOLProtocol.authTag(pin: "1234")
check(tag.count == 8, "authTag length")
check(tag != [UInt8](repeating: 0, count: 8), "non-empty PIN authTag non-zero")
check(AOLProtocol.authTag(pin: "") == [UInt8](repeating: 0, count: 8), "empty PIN zeros")

let packets: [AOLPacket] = [
    .discover,
    .announce(AOLAnnounce(port: 37419, flags: 3, deviceName: "iPhone 16 Pro")),
    .hello(AOLHello(flags: 0, deviceMask: 0x23, authTag: tag, hostName: "linux-box")),
    .helloAck(AOLHelloAck(status: 0, sessionActive: true, tvActive: true, deviceName: "Madeira")),
    .ping(1234567890123),
    .pong(9876543210987),
    .keyEvent(AOLKeyEvent(hidUsage: 0x04, pressed: true, held: [0x04, 0xE1])),
    .mouseMotion(AOLMouseMotion(dx: -17, dy: 42, wheelX: -1, wheelY: 2, buttons: 0x09)),
    .mouseButton(AOLMouseButton(buttons: 0x03, changedMask: 0x02)),
    .gamepadState(AOLGamepadState(slot: 2, connected: true, buttons: 0xF001, leftTrigger: 120, rightTrigger: 255, lx: -32768, ly: 32767, rx: -512, ry: 1024)),
    .releaseAll(1),
    .rumble(AOLRumble(slot: 1, leftMotor: 65535, rightMotor: 12345)),
    .disconnect(4),
]

for (idx, pkt) in packets.enumerated() {
    let encoded = AOLProtocol.encode(seq: UInt32(idx + 10), packet: pkt)
    guard let decoded = AOLProtocol.decode(encoded) else {
        fputs("FAIL: decode failed at index \(idx)\n", stderr)
        exit(1)
    }
    check(decoded.header.version == 1, "version mismatch")
    check(decoded.header.seq == UInt32(idx + 10), "seq mismatch")
    check(decoded.packet == pkt, "roundtrip mismatch at \(idx)")
}

// Bad / truncated packet handling
check(AOLProtocol.decode(Data([0x00, 0x01])) == nil, "short rejected")
check(AOLProtocol.decode(Data([0x58, 0x41, 1, 0, 0, 0, 0, 0])) == nil, "bad magic rejected")
check(AOLProtocol.decode(Data([0x4D, 0x41, 9, 0, 0, 0, 0, 0])) == nil, "bad version rejected")
check(AOLProtocol.decode(Data([0x4D, 0x41, 1, 0x44, 0, 0, 0, 0])) == nil, "unknown type rejected")

// Key reconciler self-healing
var reconciler = AOLHeldKeyReconciler()
_ = reconciler.apply(AOLKeyEvent(hidUsage: 0x04, pressed: true, held: [0x04]))
_ = reconciler.apply(AOLKeyEvent(hidUsage: 0x1A, pressed: true, held: [0x04, 0x1A]))
// Missed W release, now user releases A and PC sends held=[] -> W must be cleared!
let afterHeal = reconciler.apply(AOLKeyEvent(hidUsage: 0x04, pressed: false, held: []))
check(afterHeal.isEmpty, "reconciler self-healed missed release")

// Export hex frames to stdout for Go cross-check when --interop <out_dir> is passed
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--emit" {
    let dir = CommandLine.arguments[2]
    for (idx, pkt) in packets.enumerated() {
        let bin = AOLProtocol.encode(seq: UInt32(100 + idx), packet: pkt)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("swift_\(idx).bin")
        try! bin.write(to: url)
    }
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--verify-dir" {
    let dir = CommandLine.arguments[2]
    for (idx, expected) in packets.enumerated() {
        let url = URL(fileURLWithPath: dir).appendingPathComponent("go_\(idx).bin")
        let data = try! Data(contentsOf: url)
        guard let decoded = AOLProtocol.decode(data) else {
            fputs("FAIL: failed to decode go_\(idx).bin\n", stderr)
            exit(1)
        }
        check(decoded.header.seq == UInt32(200 + idx), "go seq mismatch at \(idx)")
        check(decoded.packet == expected, "Go -> Swift mismatch at \(idx): got \(decoded.packet) expected \(expected)")
    }
}
print("swift-aol-tests: OK (\(packets.count) packets)")
'''


GO_INTEROP_TEST = r'''package main

import (
	"fmt"
	"os"
	"path/filepath"
	"reflect"

	"github.com/Cat-Ling/Madeira/tools/aol/protocol"
)

func main() {
	dir := os.Args[1]
	tag := protocol.AuthTag("1234")
	packets := []protocol.Packet{
		protocol.Discover{},
		protocol.Announce{Port: 37419, Flags: 3, DeviceName: "iPhone 16 Pro"},
		protocol.Hello{Flags: 0, DeviceMask: 0x23, AuthTag: tag, HostName: "linux-box"},
		protocol.HelloAck{Status: 0, SessionActive: true, TVActive: true, DeviceName: "Madeira"},
		protocol.Ping{TimestampUS: 1234567890123},
		protocol.Pong{TimestampUS: 9876543210987},
		protocol.KeyEvent{HIDUsage: 0x04, Pressed: true, Held: []uint16{0x04, 0xE1}},
		protocol.MouseMotion{DX: -17, DY: 42, WheelX: -1, WheelY: 2, Buttons: 0x09},
		protocol.MouseButton{Buttons: 0x03, ChangedMask: 0x02},
		protocol.GamepadState{Slot: 2, Connected: true, Buttons: 0xF001, LeftTrigger: 120, RightTrigger: 255, LX: -32768, LY: 32767, RX: -512, RY: 1024},
		protocol.ReleaseAll{Reason: 1},
		protocol.Rumble{Slot: 1, LeftMotor: 65535, RightMotor: 12345},
		protocol.Disconnect{Reason: 4},
	}

	// Verify Swift -> Go
	for i, want := range packets {
		b, err := os.ReadFile(filepath.Join(dir, fmt.Sprintf("swift_%d.bin", i)))
		if err != nil {
			panic(err)
		}
		hdr, got, err := protocol.Unmarshal(b)
		if err != nil {
			panic(fmt.Errorf("swift_%d: %w", i, err))
		}
		if hdr.Seq != uint32(100+i) {
			panic(fmt.Errorf("swift_%d seq=%d want %d", i, hdr.Seq, 100+i))
		}
		if !reflect.DeepEqual(got, want) {
			panic(fmt.Errorf("swift_%d mismatch: got=%#v want=%#v", i, got, want))
		}
	}

	// Emit Go -> Swift
	for i, pkt := range packets {
		b := protocol.Marshal(uint32(200+i), pkt)
		if err := os.WriteFile(filepath.Join(dir, fmt.Sprintf("go_%d.bin", i)), b, 0o600); err != nil {
			panic(err)
		}
	}
	fmt.Printf("go-swift-interop: OK (%d packets)\n", len(packets))
}
'''


def check_static_wiring():
    def read(rel):
        p = os.path.join(ROOT, rel)
        assert os.path.isfile(p), f"missing file: {rel}"
        with open(p, "r", encoding="utf-8") as f:
            return f.read()

    settings = read("app/Madeira/SettingsPages.swift")
    for needle in ["case .aol", "Accessories Over LAN", "AccessoriesOverLANSettingsSection()"]:
        assert needle in settings, f"SettingsPages.swift missing {needle!r}"

    app_file = read("app/Madeira/MadeiraApp.swift")
    assert "AccessoriesOverLAN.shared.startIfEnabled()" in app_file

    with open(os.path.join(ROOT, "app", "Madeira", "Info.plist"), "rb") as f:
        plist = plistlib.load(f)
    bonjour = plist.get("NSBonjourServices", [])
    assert "_remotepairing-pairable-host._tcp" in bonjour, "lost JIT pairing Bonjour service"
    assert "_madeira-aol._udp" in bonjour, "missing AoL Bonjour service"

    pbx = read("app/Madeira.xcodeproj/project.pbxproj")
    assert "A1000403 /* AccessoriesOverLAN.swift in Sources */" in pbx
    assert "A2000403 /* AccessoriesOverLAN.swift */" in pbx

    gp = read("app/Madeira/GamepadInput.swift")
    for needle in ["setRemotePad(slot:", "clearRemotePads()", "remotePads"]:
        assert needle in gp, f"GamepadInput.swift missing {needle!r}"

    hw = read("app/Madeira/HardwareInput.swift")
    for needle in ["injectRemoteKey(", "injectRemoteMouse(", "releaseAllRemoteInput()"]:
        assert needle in hw, f"HardwareInput.swift missing {needle!r}"

    ed = read("app/Madeira/ExternalDisplayConsole.swift")
    for needle in ["RemoteAccessorySnapshot", "updateRemoteAccessories(", "remoteLAN"]:
        assert needle in ed, f"ExternalDisplayConsole.swift missing {needle!r}"

    _ = read("docs/ACCESSORIES_OVER_LAN.md")
    print("static-wiring: OK")


def main():
    check_static_wiring()
    if not shutil.which("swiftc"):
        print("swiftc not found on host; skipping Swift protocol test")
        return

    with tempfile.TemporaryDirectory(prefix="madeira-aol-test-") as tmp:
        swift_file = os.path.join(tmp, "aol_test.swift")
        bin_file = os.path.join(tmp, "aol_test")
        with open(swift_file, "w", encoding="utf-8") as f:
            f.write(swift_pure_source() + "\n" + SWIFT_TEST_HARNESS)

        subprocess.run(["swiftc", swift_file, "-o", bin_file], check=True)
        subprocess.run([bin_file, "--emit", tmp], check=True)

        if shutil.which("go"):
            # Write temporary Go program inside tools/aol so it resolves module directly.
            go_tmp = os.path.join(tmp, "interop.go")
            with open(go_tmp, "w", encoding="utf-8") as f:
                f.write(GO_INTEROP_TEST)
            subprocess.run(
                ["go", "run", go_tmp, tmp],
                cwd=os.path.join(ROOT, "tools", "aol"),
                check=True,
            )
            subprocess.run([bin_file, "--verify-dir", tmp], check=True)
        else:
            print("go not found on host; skipped Go<->Swift wire roundtrip")


if __name__ == "__main__":
    main()
