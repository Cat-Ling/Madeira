#!/usr/bin/env python3
"""Guard against weak C imports from newer iOS SDKs (e.g. pipe2 on iOS 27)."""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ok = True


def check(what, cond, detail=""):
    global ok
    print(("ok   " if cond else "FAIL ") + what + ("" if cond or not detail else "\n     " + str(detail)[:2000]))
    ok = ok and bool(cond)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(path.parent))
    spec.loader.exec_module(mod)
    return mod


for rel in (
    "build/ntdll-unix/shims/wine_ios_exit.h",
    "build/wineserver/config_ios.h",
    "build/win32u-unix/config_ios.h",
):
    src = (ROOT / rel).read_text()
    check(f"{rel}: undefines HAVE_PIPE2", "#undef HAVE_PIPE2" in src)

for rel in ("build/ntdll-unix/server_ios.c", "build/ntdll-unix/process_ios.c"):
    src = (ROOT / rel).read_text()
    calls = [i for i in range(len(src)) if src.startswith("pipe2(", i)]
    guarded = all(src.rfind("#ifdef HAVE_PIPE2", 0, i) > src.rfind("#endif", 0, i) for i in calls)
    check(f"{rel}: every pipe2() call sits under #ifdef HAVE_PIPE2", bool(calls) and guarded)

pkg = (ROOT / "tools/build/package-ipa.sh").read_text()
check(
    "package-ipa.sh runs check-weak-libsystem.py and check-ios-runtime-symbols.py before codesign",
    'python3 "$ROOT/tools/check-weak-libsystem.py" "$APP"' in pkg
    and 'python3 "$ROOT/tools/check-ios-runtime-symbols.py" "$APP" --auto' in pkg
    and pkg.index('check-weak-libsystem.py') < pkg.index("codesign --force")
    and pkg.index('check-ios-runtime-symbols.py') < pkg.index("codesign --force"),
)

cwl = load("check_weak_libsystem", ROOT / "tools/check-weak-libsystem.py")
fixture = """/x/Madeira [arm64]:
    -imports:
      0x0601  _pipe2 [weak-import] (from libSystem)
      0x0602  __availability_version_check [weak-import] (from libSystem)
      0x0603  _os_sync_wake_by_address_any [weak-import] (from libSystem)
      0x0608  __dyld_get_dlopen_image_header [weak-import] (from libSystem)
      0x0604  _$s10Foundation4DateV2geoiySbAC_ACtFZ [weak-import] (from Foundation)
      0x0605  _OBJC_CLASS_$_UIHingeInteraction [weak-import] (from UIKit)
      0x0606  _pipe (from libSystem)
      0x0607  __ZNSt3__1newthing [weak-import] (from libc++)
            _pthread_mutexattr_init [weak-import] (from libSystem)
"""
names = [s for s, _ in cwl.weak_c_imports(fixture)]
check(
    "weak_c_imports filters weak C imports from libSystem/libc++",
    names == [
        "_pipe2",
        "__availability_version_check",
        "_os_sync_wake_by_address_any",
        "__dyld_get_dlopen_image_header",
        "__ZNSt3__1newthing",
        "_pthread_mutexattr_init",
    ],
    names,
)
check(
    "KNOWN allows known guarded imports while rejecting _pipe2",
    [n for n in names if n not in cwl.KNOWN] == ["_pipe2", "__ZNSt3__1newthing"],
)

crs = load("check_ios_runtime_symbols", ROOT / "tools/check-ios-runtime-symbols.py")
check(
    "check-ios-runtime-symbols leaf() normalizes system install names",
    [
        crs.leaf(p)
        for p in (
            "/usr/lib/libSystem.B.dylib",
            "/usr/lib/libc++.1.dylib",
            "/usr/lib/libobjc.A.dylib",
            "/System/Library/Frameworks/SwiftUI.framework/SwiftUI",
            "/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit",
        )
    ]
    == ["libSystem", "libc++", "libobjc", "SwiftUI", "IOKit"],
)

dce = load("dyld_cache_exports", ROOT / "tools/dyld_cache_exports.py")
root = b"\x00\x02" + b"_a\x00" + b"\x0a" + b"_b\x00" + b"\x0e"
node_a = b"\x02\x00\x00\x00"
node_b = b"\x02\x00\x00\x01" + b"c\x00" + b"\x15"
node_c = b"\x02\x00\x00\x00"
trie = root + node_a + node_b + node_c
dce_src = (ROOT / "tools/dyld_cache_exports.py").read_text()
start = dce_src.index('            stack = [(0, b"")]')
loop = dce_src[start:dce_src.index('        self._cache[install] = (frozenset(names), tuple(reexports))')]
ns = {"uleb": dce.uleb}
exec("def _walk(data, names):\n" + "\n".join(line[8:] for line in loop.splitlines()) + "\n    return names\n", ns)
check("dyld_cache_exports trie walk extracts nested terminal exports", ns["_walk"](trie, set()) == {"_a", "_b", "_bc"})

print("PASS: weak C imports and runtime symbol guards" if ok else "FAILED: weak C imports and runtime symbol guards")
sys.exit(0 if ok else 1)
