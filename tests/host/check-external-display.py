#!/usr/bin/env python3
"""Host checks for dedicated External Display Console Mode, aspect/overscan math, and wiring."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app" / "Madeira"
ok = True


def check(what, cond, detail=""):
    global ok
    print(("ok   " if cond else "FAIL ") + what + ("" if cond or not detail else "\n     " + str(detail)[:2000]))
    ok = ok and bool(cond)


guest_src = (APP / "GuestDisplay.swift").read_text()
ext_src = (APP / "ExternalDisplayConsole.swift").read_text()

# Extract pure Foundation/CoreGraphics sections before `#if canImport(UIKit)`.
ext_pure = ext_src.split("#if canImport(UIKit)", 1)[0]
guest_pure = "\n".join(line for line in guest_src.splitlines() if not line.startswith("import "))

harness = f"""
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

func winios_display_mode_changed(_ w: Int32, _ h: Int32) {{}}

{guest_pure}
{ext_pure}

var failures = 0
func expect(_ cond: Bool, _ msg: String) {{
    print((cond ? "ok   " : "FAIL ") + msg)
    if !cond {{ failures += 1 }}
}}

// 1. Overscan safe bounds
let tv1080 = CGRect(x: 0, y: 0, width: 1920, height: 1080)
let safe0 = ExternalDisplayLayout.safeBounds(for: tv1080, overscanPercent: 0)
expect(safe0 == tv1080, "0% overscan preserves full bounds")
let safe5 = ExternalDisplayLayout.safeBounds(for: tv1080, overscanPercent: 5)
expect(abs(safe5.width - 1728) < 0.01 && abs(safe5.height - 972) < 0.01, "5% overscan insets each edge by 5%")
let safeClamp = ExternalDisplayLayout.safeBounds(for: tv1080, overscanPercent: 25)
expect(abs(safeClamp.width - 1536) < 0.01, "overscan clamps to 10% max")

// 2. DisplayLayout Fit, Fill, Stretch, Aspect & aspect overrides
let rFit = ExternalDisplayLayout.rect(guest: CGSize(width: 1280, height: 720), bounds: tv1080, mode: .fit)
expect(abs(rFit.width - 1920) < 0.01 && abs(rFit.height - 1080) < 0.01, "16:9 guest fits 1080p TV edge to edge")

let r4x3On16x9 = ExternalDisplayLayout.rect(guest: CGSize(width: 1280, height: 720), bounds: tv1080, mode: .fit, aspectOverride: .ratio4x3)
expect(abs(r4x3On16x9.width - 1440) < 0.5 && abs(r4x3On16x9.height - 1080) < 0.5 && abs(r4x3On16x9.minX - 240) < 0.5, "4:3 override pillarboxes cleanly inside 1080p TV")

let rStretch = ExternalDisplayLayout.rect(guest: CGSize(width: 1024, height: 768), bounds: tv1080, mode: .stretch, aspectOverride: .ratio4x3, overscanPercent: 5)
expect(rStretch == safe5, "stretch fills safe overscan bounds")

let rFill = ExternalDisplayLayout.rect(guest: CGSize(width: 1024, height: 768), bounds: tv1080, mode: .fill)
expect(abs(rFill.width - 1920) < 0.5 && abs(rFill.height - 1440) < 0.5, "4:3 guest in fill mode covers 16:9 TV height-wise")

// 3. Resolution presets
expect(ExternalResolutionPreset.auto.resolve(externalPixels: CGSize(width: 3840, height: 2160), gameResolution: "1408x648") == "1920x1080", "4K 16:9 TV auto resolves to 1920x1080")
expect(ExternalResolutionPreset.auto.resolve(externalPixels: CGSize(width: 1280, height: 720), gameResolution: "1408x648") == "1280x720", "720p TV auto resolves to 1280x720")
expect(ExternalResolutionPreset.auto.resolve(externalPixels: CGSize(width: 2560, height: 1080), gameResolution: "1408x648") == "2560x1080", "21:9 ultrawide monitor auto resolves to 2560x1080")
expect(ExternalResolutionPreset.gameDefault.resolve(externalPixels: CGSize(width: 1920, height: 1080), gameResolution: "1408x648") == "1408x648", "gameDefault preserves per-game resolution")

// 4. Console navigation & hit-testing
expect(ExternalConsoleNavigation.stepIndex(0, delta: -1, count: 4) == 3, "stepIndex wraps backwards")
expect(ExternalConsoleNavigation.stepIndex(3, delta: 1, count: 4) == 0, "stepIndex wraps forwards")
let hit = ExternalConsoleNavigation.hitTest(point: CGPoint(x: 150, y: 80), targets: [
    ("tab:games", CGRect(x: 100, y: 50, width: 120, height: 40)),
    ("tab:display", CGRect(x: 240, y: 50, width: 120, height: 40)),
])
expect(hit == "tab:games", "hitTest resolves matching TV console target")

exit(failures == 0 ? 0 : 1)
"""

swiftc = shutil.which("swiftc")
if swiftc:
    with tempfile.TemporaryDirectory() as d:
        src = Path(d) / "test_external.swift"
        exe = Path(d) / "test_external"
        src.write_text(harness)
        comp = subprocess.run([swiftc, str(src), "-o", str(exe)], capture_output=True, text=True)
        check("pure ExternalDisplayConsole + GuestDisplay compiles with swiftc", comp.returncode == 0, comp.stderr)
        if comp.returncode == 0:
            run = subprocess.run([str(exe)], capture_output=True, text=True)
            print(run.stdout.rstrip())
            check("pure external display geometry & navigation tests pass", run.returncode == 0, run.stderr)
else:
    print("FAIL: swiftc required to run check-external-display.py")
    ok = False

pbx = (ROOT / "app/Madeira.xcodeproj/project.pbxproj").read_text()
app_swift = (APP / "MadeiraApp.swift").read_text()
content = (APP / "ContentView.swift").read_text()
library = (APP / "Library.swift").read_text()
hw = (APP / "HardwareInput.swift").read_text()
fps = (APP / "FPSOverlay.swift").read_text()

check("project.pbxproj builds ExternalDisplayConsole.swift", "ExternalDisplayConsole.swift in Sources" in pbx and "path = ExternalDisplayConsole.swift;" in pbx)
check("MadeiraApp starts ExternalDisplay.shared", "ExternalDisplay.shared.start()" in app_swift)
check("ContentView mounts game layer and Companion Deck", ".mountGameLayer(" in content and "ExternalPhoneCompanionView()" in content)
check("Library.swift isolates gamepad input when TV Console owns input", "!ExternalDisplay.shared.consoleOwnsInput" in library and "ExternalLibraryBanner()" in library)
check("HardwareInput.swift routes keyboard/mouse to TV Console", "ExternalConsoleController.shared.handleKey" in hw and "ExternalConsoleController.shared.moveCursor" in hw and "consoleInputActive" in hw)
check("FPSOverlay.swift honors active external display refresh rate", "ExternalDisplay.currentActiveMaxFPS" in fps)
check("GuestDisplay.swift applies externalResolutionOverride", "externalResolutionOverride" in guest_src)

print("PASS: ExternalDisplay Console & Companion wiring" if ok else "FAILED: ExternalDisplay Console & Companion checks")
sys.exit(0 if ok else 1)
