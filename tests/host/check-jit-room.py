#!/usr/bin/env python3
"""Host checks for zero-footprint JIT pool room bitmap and virtual_ios.c wiring."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "build/ntdll-unix/pp_jit_room.h"
VIOS = ROOT / "build/ntdll-unix/virtual_ios.c"
ok = True


def check(what, cond, detail=""):
    global ok
    print(("ok   " if cond else "FAIL ") + what + ("" if cond or not detail else "\n     " + str(detail)[:2000]))
    ok = ok and bool(cond)


harness = f"""
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "{HEADER.as_posix()}"

static int g_calls = 0;
static size_t g_last_off = 0;
static size_t g_last_len = 0;
static size_t g_total_bytes = 0;
static unsigned long g_fake_taken = 0;

static unsigned long test_take(void *ctx, size_t off, size_t len) {{
    (void)ctx;
    g_calls++;
    g_last_off = off;
    g_last_len = len;
    g_total_bytes += len;
    return g_fake_taken ? (len / PPJR_PAGE) : 0;
}}

int main(void) {{
    const size_t pool_size = 64 * PPJR_PAGE;
    const size_t first_off = PPJR_PAGE;
    unsigned char bits[64 / 8];
    struct ppjr r;

    /* Invalid inputs fail cleanly without setting claimed. */
    if (ppjr_init(&r, bits, pool_size, 0x100) != -1 || r.claimed != NULL) return 1;
    if (ppjr_init(&r, bits, pool_size, pool_size) != -1 || r.claimed != NULL) return 2;

    memset(bits, 0, sizeof(bits));
    if (ppjr_init(&r, bits, pool_size, first_off) != 0) return 3;
    if (ppjr_room_bytes(&r) != 63 * PPJR_PAGE) return 4;

    /* Split-pool hole pre-marking: [10..14) pages excluded from room and never passed to take. */
    if (ppjr_mark_claimed(&r, 10 * PPJR_PAGE, 4 * PPJR_PAGE) != 4) return 5;
    if (ppjr_room_bytes(&r) != 59 * PPJR_PAGE) return 6;

    /* Claim across the pre-marked hole: must split into two contiguous non-hole take() runs. */
    g_fake_taken = 1;
    if (ppjr_claim(&r, 8 * PPJR_PAGE, 8 * PPJR_PAGE, test_take, NULL) != 4) return 7;
    if (g_calls != 2 || g_total_bytes != 4 * PPJR_PAGE) return 8;
    if (ppjr_room_bytes(&r) != 55 * PPJR_PAGE) return 9;
    if (r.taken != 4) return 10;

    /* Idempotent re-claim does zero work. */
    if (ppjr_claim(&r, 8 * PPJR_PAGE, 8 * PPJR_PAGE, test_take, NULL) != 0 || g_calls != 2) return 11;

    /* Page 0 is below first_off so it is never claimed; clamping handles huge size without overflow. */
    g_fake_taken = 0;
    size_t rem = ppjr_claim(&r, 0, (size_t)-1, test_take, NULL);
    if (rem != 55 || ppjr_room_bytes(&r) != 0) return 12;

    printf("ok   pp_jit_room host invariants pass\\n");
    return 0;
}}
"""

cc = shutil.which("cc") or shutil.which("clang") or shutil.which("gcc")
if cc:
    with tempfile.TemporaryDirectory() as d:
        c_path = Path(d) / "test_jit_room.c"
        exe_path = Path(d) / "test_jit_room"
        c_path.write_text(harness)
        comp = subprocess.run([cc, "-Wall", "-Wextra", "-Werror", str(c_path), "-o", str(exe_path)],
                              capture_output=True, text=True)
        check("pp_jit_room.h compiles cleanly under -Wall -Wextra -Werror", comp.returncode == 0, comp.stderr)
        if comp.returncode == 0:
            run = subprocess.run([str(exe_path)], capture_output=True, text=True)
            print(run.stdout.rstrip())
            check("pp_jit_room unit tests pass", run.returncode == 0, run.stderr)
else:
    check("C compiler available", False)

vios_src = VIOS.read_text()
check("virtual_ios.c includes pp_jit_room.h", '#include "pp_jit_room.h"' in vios_src)
check("virtual_ios.c initializes room after JIT pool init", "ios_pool_room_init( jit_pool_size, jit_pool_offset );" in vios_src)
check("virtual_ios.c skips split-pool holes in ios_pool_room_init", "ppjr_mark_claimed" in vios_src and "IOS_POOL_IN_HOLE" in vios_src)
check("virtual_ios.c claims room pages on allocation and tail carve",
      "ios_pool_room_claim( off, alloc_size );" in vios_src and "ios_pool_room_claim( pool_tail_off, alloc_size );" in vios_src)
rx_pos = vios_src.find("for (o = 0; o < head; o += 0x4000) { if (IOS_POOL_IN_HOLE(o)) continue; sink += rx[o];")
rw_pos = vios_src.find("for (o = 0; o < head; o += 0x4000) { if (IOS_POOL_IN_HOLE(o)) continue; sink += rw[o];")
check("virtual_ios.c warmer touches RX before RW", 0 <= rx_pos < rw_pos)

print("PASS: JIT pool room" if ok else "FAILED: JIT pool room")
sys.exit(0 if ok else 1)
