#!/usr/bin/env python3
"""Host checks for Playport host-abort forensic helper (pp_abort_why.h) and wiring."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "build/ntdll-unix/pp_abort_why.h"
SIG = ROOT / "build/ntdll-unix/signal_arm64_ios.c"
ok = True


def check(what, cond, detail=""):
    global ok
    print(("ok   " if cond else "FAIL ") + what + ("" if cond or not detail else "\n     " + str(detail)[:2000]))
    ok = ok and bool(cond)


harness = f"""
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "{HEADER.as_posix()}"

struct fake_mach {{
    struct ppaw_mach_header mh;
    struct ppaw_segment seg;
    struct ppaw_section sec;
}};

struct fake_frame {{
    uint64_t next;
    uint64_t ret;
}};

static int read_mem(uint64_t addr, uint64_t frame[2], void *ctx) {{
    (void)ctx;
    if (addr == 0xdeadbeefULL) return 0;
    const struct fake_frame *f = (const struct fake_frame *)(uintptr_t)addr;
    frame[0] = f->next;
    frame[1] = f->ret;
    return 1;
}}

int main(void) {{
    struct fake_mach img;
    memset(&img, 0, sizeof(img));
    img.mh.magic = PPAW_MH_MAGIC_64;
    img.mh.ncmds = 1;
    img.mh.sizeofcmds = sizeof(img.seg) + sizeof(img.sec);
    img.seg.cmd = PPAW_LC_SEGMENT_64;
    img.seg.cmdsize = sizeof(img.seg) + sizeof(img.sec);
    img.seg.nsects = 1;
    memcpy(img.sec.sectname, "__crash_info", 12);
    img.sec.addr = 0x10000;
    img.sec.size = 64;

    uint64_t addr = 0, size = 0;
    if (!ppaw_find_section(&img, 0x2000, "__crash_info", &addr, &size)) return 1;
    if (addr != 0x12000 || size != 64) return 2;
    if (ppaw_find_section(&img, 0, "__missing", &addr, &size)) return 3;

    struct ppaw_crash_info info;
    memset(&info, 0, sizeof(info));
    uint64_t msgs[2], cause = 99;
    if (ppaw_crash_messages(&info, sizeof(info), msgs, &cause) != 0) return 4;
    info.version = 5;
    info.message = 0x1111;
    info.message2 = 0x2222;
    info.abort_cause = 0x3333;
    if (ppaw_crash_messages(&info, sizeof(info), msgs, &cause) != 2) return 5;
    if (msgs[0] != 0x1111 || msgs[1] != 0x2222 || cause != 0x3333) return 6;

    /* Valid frame chain -> then cycle/refusal termination. */
    struct fake_frame f[3];
    memset(f, 0, sizeof(f));
    f[0].next = (uint64_t)(uintptr_t)&f[1]; f[0].ret = 0xaaa1;
    f[1].next = (uint64_t)(uintptr_t)&f[2]; f[1].ret = 0xaaa2;
    f[2].next = (uint64_t)(uintptr_t)&f[0]; f[2].ret = 0xaaa3; /* backwards cycle stops */
    uint64_t ret[8];
    unsigned n = ppaw_walk((uint64_t)(uintptr_t)&f[0], read_mem, NULL, ret, 8);
    if (n != 3 || ret[0] != 0xaaa1 || ret[1] != 0xaaa2 || ret[2] != 0xaaa3) return 7;

    printf("ok   pp_abort_why host invariants pass\\n");
    return 0;
}}
"""

cc = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
if cc:
    with tempfile.TemporaryDirectory() as d:
        c_path = Path(d) / "test_abort_why.c"
        exe_path = Path(d) / "test_abort_why"
        c_path.write_text(harness)
        comp = subprocess.run([cc, "-Wall", "-Wextra", "-Werror", str(c_path), "-o", str(exe_path)],
                              capture_output=True, text=True)
        check("pp_abort_why.h compiles cleanly under -Wall -Wextra -Werror", comp.returncode == 0, comp.stderr)
        if comp.returncode == 0:
            run = subprocess.run([str(exe_path)], capture_output=True, text=True)
            print(run.stdout.rstrip())
            check("pp_abort_why unit tests pass", run.returncode == 0, run.stderr)
else:
    check("C compiler available", False)

sig_src = SIG.read_text()
check("signal_arm64_ios.c includes pp_abort_why.h", '#include "pp_abort_why.h"' in sig_src)
check("abrt_handler calls ios_log_host_abort", "ios_log_host_abort( (ucontext_t *)sigcontext );" in sig_src)

print("PASS: host abort forensics" if ok else "FAILED: host abort forensics")
sys.exit(0 if ok else 1)
