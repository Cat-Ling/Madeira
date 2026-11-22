#!/usr/bin/env python3
"""Verify NutsEmu build 1977 ports in Madeira without needing an iOS SDK."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def extract_block(text: str, anchor: str, end_marker: str = "\n}\n") -> str:
    start = text.index(anchor)
    end = text.index(end_marker, start) + len(end_marker)
    return text[start:end]


def verify_vkd3d_patches() -> None:
    src_dir = ROOT / "toolchains/vkd3d-proton"
    if not (src_dir / "meson.build").exists():
        raise AssertionError(f"missing vkd3d-proton upstream checkout at {src_dir}")

    patches = sorted((ROOT / "build/vkd3d-proton/patches").glob("[0-9]*.patch"))
    names = [p.name for p in patches]
    assert len(patches) == 10, f"expected 10 vkd3d-proton patches, got {names}"

    patches_md = (ROOT / "build/vkd3d-proton/patches/PATCHES.md").read_text(encoding="utf-8")
    for name in names:
        assert name in patches_md, f"{name} missing from PATCHES.md"

    with tempfile.TemporaryDirectory(prefix="madeira-vkd3d-test-") as tmp:
        work = Path(tmp) / "src"
        shutil.copytree(src_dir, work, symlinks=True, ignore=shutil.ignore_patterns(".git"))
        for patch_file in patches:
            res = subprocess.run(
                ["patch", "-s", "-p1", "--batch", "--forward", "-d", str(work)],
                input=patch_file.read_bytes(),
                capture_output=True,
            )
            assert res.returncode == 0, (
                f"patch {patch_file.name} failed:\n"
                f"{res.stdout.decode(errors='replace')}\n{res.stderr.decode(errors='replace')}"
            )
        rejs = list(work.rglob("*.rej"))
        assert not rejs, f"unexpected .rej files: {rejs}"

        tls = (work / "subprojects/dxil-spirv/util/thread_local_allocator.cpp").read_text(encoding="utf-8")
        assert "#if defined(WINE_TEB_TSD_SLOT) || defined(_WIN32)" in tls
        assert "TlsAlloc()" in tls and "TlsGetValue(" in tls and "TlsSetValue(" in tls

        res_c = (work / "libs/vkd3d/resource.c").read_text(encoding="utf-8")
        assert "VKD3D_MIN_BUFFER_ALIGNMENT" in res_c

        dev_c = (work / "libs/vkd3d/device.c").read_text(encoding="utf-8")
        assert "pool_info.queryCount = 256;" in dev_c

        state_c = (work / "libs/vkd3d/state.c").read_text(encoding="utf-8")
        assert "d3d12_pipeline_state_needs_rtv_variant" in state_c

        mem_c = (work / "libs/vkd3d/memory.c").read_text(encoding="utf-8")
        assert "VK_DRIVER_ID_MESA_KOSMICKRISP" in mem_c

    print("PASS: vkd3d-proton patches 0001-0010 apply cleanly and contain expected ARM64EC/KosmicKrisp fixes")


def verify_signal_resuspend() -> None:
    src = (ROOT / "build/ntdll-unix/signal_arm64_ios.c").read_text(encoding="utf-8")
    block = src[src.index("/* NutsEmu 0190:"):src.index("static void usr1_handler(")]
    # Drop the dyld-based initializer so host Linux tests can populate ios_lock_code directly.
    core = block[:block.index("static void ios_init_resuspend_impl(")]

    usr1 = extract_block(src, "static void usr1_handler(")
    assert "if (ios_inside_lock_code( ucontext ) && ios_resuspend_later())" in usr1
    assert usr1.index("ios_inside_lock_code(") < usr1.index("NtGetContextThread(")

    init_proc = extract_block(src, "void signal_init_process(void)")
    assert "ios_init_resuspend();" in init_proc

    harness = r"""
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>

typedef uintptr_t ULONG_PTR;
typedef int BOOL;
typedef int LONG;
typedef unsigned int ULONG;
typedef unsigned int mach_port_t;
typedef int semaphore_t;
typedef int kern_return_t;
#define TRUE 1
#define FALSE 0
#define KERN_SUCCESS 0
#define ARRAY_SIZE(x) (sizeof(x) / sizeof((x)[0]))

struct fake_ucontext {
    ULONG_PTR pc;
    ULONG_PTR lr;
    ULONG_PTR fp;
};
#define ucontext_t struct fake_ucontext
#define PC_sig(c) ((c)->pc)
#define LR_sig(c) ((c)->lr)
#define FP_sig(c) ((c)->fp)

struct ntdll_thread_data {
    void *kernel_stack;
};
static struct ntdll_thread_data g_thread_data;
static size_t kernel_stack_size = 4096;
static struct ntdll_thread_data *ntdll_get_thread_data(void) { return &g_thread_data; }

static mach_port_t g_next_port = 100;
static int g_deallocated = 0;
static int g_sem_signals = 0;
static int g_kills = 0;
static mach_port_t mach_thread_self(void) { return g_next_port++; }
static mach_port_t mach_task_self(void) { return 1; }
static kern_return_t mach_port_deallocate(mach_port_t task, mach_port_t port) { (void)task; (void)port; g_deallocated++; return KERN_SUCCESS; }
static kern_return_t semaphore_signal(semaphore_t sem) { (void)sem; g_sem_signals++; return KERN_SUCCESS; }
static kern_return_t semaphore_wait(semaphore_t sem) { (void)sem; return KERN_SUCCESS; }
int __pthread_kill(mach_port_t port, int sig) { (void)port; (void)sig; g_kills++; return 0; }
""" + core + r"""
int main(void) {
    uint64_t stack[64] = {0};
    g_thread_data.kernel_stack = stack;
    kernel_stack_size = sizeof(stack);

    ios_lock_code[0].start = 0x10000;
    ios_lock_code[0].end = 0x20000;
    ios_lock_code_count = 1;
    ios_resuspend_ready = TRUE;

    /* 1. PC inside lock code triggers deferral. */
    ucontext_t ctx = { .pc = 0x10500, .lr = 0x30000, .fp = 0 };
    assert(ios_inside_lock_code(&ctx) == TRUE);

    /* 2. LR inside lock code triggers deferral. */
    ctx = (ucontext_t){ .pc = 0x30000, .lr = 0x1ffff, .fp = 0 };
    assert(ios_inside_lock_code(&ctx) == TRUE);

    /* 3. Frame chain on kernel stack with saved LR inside lock code triggers deferral. */
    stack[4] = (ULONG_PTR)&stack[10];
    stack[5] = 0x35000;
    stack[10] = (ULONG_PTR)&stack[16];
    stack[11] = 0x12340;
    stack[16] = 0;
    stack[17] = 0x40000;
    ctx = (ucontext_t){ .pc = 0x30000, .lr = 0x31000, .fp = (ULONG_PTR)&stack[4] };
    assert(ios_inside_lock_code(&ctx) == TRUE);

    /* 4. Frame chain entirely outside lock code does NOT defer. */
    stack[11] = 0x39000;
    assert(ios_inside_lock_code(&ctx) == FALSE);

    /* 5. Out-of-bounds FP safely terminates without reading invalid memory. */
    ctx = (ucontext_t){ .pc = 0x30000, .lr = 0x31000, .fp = 0xdeadbeef };
    assert(ios_inside_lock_code(&ctx) == FALSE);

    /* 6. Queueing into ios_resuspend_slots succeeds up to IOS_RESUSPEND_SLOTS, then fails cleanly. */
    for (int i = 0; i < IOS_RESUSPEND_SLOTS; i++) {
        assert(ios_resuspend_later() == TRUE);
    }
    assert(g_sem_signals == IOS_RESUSPEND_SLOTS);
    assert(ios_resuspend_count == IOS_RESUSPEND_SLOTS);
    assert(ios_resuspend_later() == FALSE);
    assert(g_deallocated == 1);

    (void)ios_resuspend_thread;
    puts("PASS: signal_arm64_ios.c host-lock deferral and resuspend queue checks");
    return 0;
}
"""
    with tempfile.TemporaryDirectory(prefix="madeira-sig-test-") as tmp:
        c_path = Path(tmp) / "sig_test.c"
        exe_path = Path(tmp) / "sig_test"
        c_path.write_text(harness, encoding="utf-8")
        cc = os.environ.get("CC", "cc")
        flags = [cc, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                 "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
                 str(c_path), "-o", str(exe_path)]
        res = subprocess.run(flags, capture_output=True, text=True)
        if res.returncode != 0:
            flags = [cc, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                     str(c_path), "-o", str(exe_path)]
            subprocess.run(flags, check=True)
        run = subprocess.run([str(exe_path)], capture_output=True, text=True, check=True)
        print(run.stdout, end="")


def verify_spawnvp_open_url() -> None:
    proc = (ROOT / "build/ntdll-unix/process_ios.c").read_text(encoding="utf-8")
    fn = extract_block(proc, "NTSTATUS WINAPI __wine_unix_spawnvp(")

    bridge_h = (ROOT / "app/Madeira/WineProcessBridge.h").read_text(encoding="utf-8")
    bridge_m = (ROOT / "app/Madeira/WineProcessBridge.m").read_text(encoding="utf-8")
    assert "int wine_host_open_url(const char *url);" in bridge_h
    assert "#import <UIKit/UIKit.h>" in bridge_m
    assert "int wine_host_open_url(const char *url)" in bridge_m
    assert "openURL:nsurl" in bridge_m

    harness = r"""
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef uint32_t NTSTATUS;
#define WINAPI
#define WINE_IOS 1
#define STATUS_SUCCESS 0x00000000u
#define STATUS_NOT_SUPPORTED 0xc00000bbu

static char last_url[256];
static int next_ret = 1;
static int call_count = 0;

int wine_host_open_url(const char *url) {
    call_count++;
    snprintf(last_url, sizeof(last_url), "%s", url ? url : "");
    return next_ret;
}
""" + fn + r"""
int main(void) {
    char *https_argv[] = { "winebrowser.exe", "https://example.com/login?x=1", NULL };
    assert(__wine_unix_spawnvp(https_argv, 0) == STATUS_SUCCESS);
    assert(call_count == 1 && strcmp(last_url, "https://example.com/login?x=1") == 0);

    char *http_argv[] = { "winebrowser.exe", "-nohome", "http://127.0.0.1:8080/", NULL };
    assert(__wine_unix_spawnvp(http_argv, 1) == STATUS_SUCCESS);
    assert(call_count == 2 && strcmp(last_url, "http://127.0.0.1:8080/") == 0);

    char *mail_argv[] = { "winebrowser.exe", "mailto:support@example.com", NULL };
    assert(__wine_unix_spawnvp(mail_argv, 0) == STATUS_SUCCESS);
    assert(call_count == 3 && strcmp(last_url, "mailto:support@example.com") == 0);

    char *other_argv[] = { "notepad.exe", "readme.txt", NULL };
    assert(__wine_unix_spawnvp(other_argv, 0) == STATUS_NOT_SUPPORTED);
    assert(call_count == 3);

    char *short_argv[] = { "https://example.com", NULL };
    assert(__wine_unix_spawnvp(short_argv, 0) == STATUS_NOT_SUPPORTED);
    assert(call_count == 3);

    assert(__wine_unix_spawnvp(NULL, 0) == STATUS_NOT_SUPPORTED);

    next_ret = 0;
    assert(__wine_unix_spawnvp(https_argv, 0) == STATUS_NOT_SUPPORTED);
    assert(call_count == 4);

    puts("PASS: __wine_unix_spawnvp URL/mailto handoff and WineProcessBridge wiring");
    return 0;
}
"""
    with tempfile.TemporaryDirectory(prefix="madeira-spawnvp-test-") as tmp:
        c_path = Path(tmp) / "spawnvp_test.c"
        exe_path = Path(tmp) / "spawnvp_test"
        c_path.write_text(harness, encoding="utf-8")
        cc = os.environ.get("CC", "cc")
        flags = [cc, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter",
                 "-rdynamic", "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
                 str(c_path), "-ldl", "-o", str(exe_path)]
        res = subprocess.run(flags, capture_output=True, text=True)
        if res.returncode != 0:
            flags = [cc, "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter",
                     "-rdynamic", str(c_path), "-ldl", "-o", str(exe_path)]
            subprocess.run(flags, check=True)
        run = subprocess.run([str(exe_path)], capture_output=True, text=True, check=True)
        print(run.stdout, end="")


def verify_build_sh_transforms() -> None:
    build_sh = (ROOT / "build/ntdll-unix/build.sh").read_text(encoding="utf-8")
    section = build_sh[build_sh.index('        sync)'):build_sh.index('        *)')]
    assert "thread_switch( MACH_PORT_NULL, SWITCH_OPTION_NONE, 0 )" in section
    assert "case IP_RECVTOS:" in section
    assert "fstat( fd, &st )" in section

    wine11_unix = Path("/mnt/fastcache/nutsemu/nutsemu-build-1977/wine-11.18/third_party/wine/dlls/ntdll/unix")
    if not (wine11_unix / "sync.c").exists():
        raise AssertionError(f"missing reference Wine sources at {wine11_unix}")

    with tempfile.TemporaryDirectory(prefix="madeira-ntdll-buildsh-") as tmp:
        tmp_dir = Path(tmp)
        obj_dir = tmp_dir / "obj"
        obj_dir.mkdir()
        driver = tmp_dir / "run_transforms.sh"
        body = section.replace('compile_one ', 'true ')
        # Test both upstream Wine 11.18 sources and synthetic Madeira Wine 11.4 variants.
        for label, use_madeira_variants in [("wine-11.18", False), ("madeira-wine-11.4", True)]:
            case_obj = obj_dir / label
            case_obj.mkdir()
            src_dir = tmp_dir / label
            src_dir.mkdir()
            for fname in ("sync.c", "socket.c", "file.c"):
                text = (wine11_unix / fname).read_text(encoding="utf-8")
                if use_madeira_variants:
                    if fname == "sync.c":
                        text = text.replace(
                            '#include "config.h"',
                            '#include "config.h"\n#include "../../../../build/madeira_cfg.h"',
                        ).replace(
                            "NTSTATUS WINAPI NtYieldExecution(void)\n{",
                            "NTSTATUS WINAPI NtYieldExecution(void)\n{\n    static __thread unsigned ios_yield_streak;\n    (void)ios_yield_streak;",
                        )
                    elif fname == "file.c":
                        text = text.replace(
                            "static int fd_get_file_info(",
                            "static int madeira_fd_stat_only(void) { return 0; }\nstatic int fd_get_file_info(",
                        )
                (src_dir / fname).write_text(text, encoding="utf-8")

            script = (
                f"set -euo pipefail\n"
                f"REPO_ROOT={str(ROOT)!r}\n"
                f"OBJ_DIR={str(case_obj)!r}\n"
                f"for name in sync socket file; do\n"
                f"  src={str(src_dir)!r}/$name.c\n"
                f"  case \"$name\" in\n"
                f"{body}\n"
                f"  esac\n"
                f"done\n"
            )
            driver.write_text(script, encoding="utf-8")
            subprocess.run(["bash", str(driver)], check=True)

            sync_out = (case_obj / "sync_ios.c").read_text(encoding="utf-8")
            assert "<mach/thread_switch.h>" in sync_out
            assert "thread_switch( MACH_PORT_NULL, SWITCH_OPTION_NONE, 0 );" in sync_out
            if not use_madeira_variants:
                assert "now - streak_start >= 2000000" in sync_out

            sock_out = (case_obj / "socket_ios.c").read_text(encoding="utf-8")
            assert sock_out.count("case IP_RECVTOS:") == 1

            file_out = (case_obj / "file_ios.c").read_text(encoding="utf-8")
            if not use_madeira_variants:
                q_start = file_out.index("NTSTATUS WINAPI NtQueryInformationFile(")
                q_end = file_out.index("\n}\n", q_start)
                q_part = file_out[q_start:q_end]
                assert q_part.count("if (fstat( fd, &st ) == -1)") == 3
                assert q_part.count("fill_file_info( &st, 0, ") == 3
                # Ensure fill_file_info itself was not modified.
                assert "fill_file_info(" in file_out[:q_start]

    print("PASS: build/ntdll-unix/build.sh transforms verified for both upstream Wine and Madeira Wine")


def main() -> int:
    verify_vkd3d_patches()
    verify_signal_resuspend()
    verify_spawnvp_open_url()
    verify_build_sh_transforms()
    print("PASS: all NutsEmu 1977 ports verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
