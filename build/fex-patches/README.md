# Madeira's FEX patches

Changes to FEX that Madeira needs and that live in this repository, not in
the FEX submodule's repository. `apply.sh` applies them, in file-name order,
to the FEX working tree before `build/fex-arm64ec/build.sh` and
`build/fex-wow64/build.sh` build `xtajit64.dll` and `xtajit.dll`; it skips a
patch that is already applied, and `apply.sh --revert` takes them out. The
FEX submodule pin does not change.

These patches are for Madeira only and are not to be sent to FEX-Emu.

| Patch | What it fixes |
|---|---|
| `0001-windows-ios-smc-traps-per-16k-host-page.patch` | Self-modifying-code write traps per 16 KB iOS host page, both modules (The Escapists 2, Project Zomboid) |
| `0002-bcd-fex-correctness-and-ios-fixes.patch` | Ports FEX correctness and iOS module fixes from `thebcd69/bcd-games`: redundant `REP`/`REPNE` prefixes on `BTC`/`BSF`/`BSR`/`MOVSX`/`CMOVcc`, 32-bit `0x82` ALU opcode alias, opt-in inline split-lock atomics (`MADEIRA_FEX_SPLIT_LOCK=1`), opt-in `MOV moffs` RIP tracking (`MADEIRA_FEX_MOFFS_RIP=1`), opt-in classic CPUID bits (`MADEIRA_FEX_CPUID_CLASSIC=1/2`), pool allocator null reclaim/retry, invalidation null-thread skip, opt-in `MonoBackpatcherWrite` unlocked miss (`MADEIRA_MONO_BP_UNLOCKED_MISS=1`), WOW64 recursive `ThreadCreationMutex`, WOW64 thread-map ctor guard (iOS 18) and `STATUS_NO_MEMORY` unwind, stale DEP promotion cleanup, ARM64EC `ThreadTerm` CPU-area clear, no-CPU-area native ARM64 thread guards, and teardown exception handoff. |
| `0003-bcd-fex-x87-signal-and-int64-preservation.patch` | Ports x87 state preservation across signal and WOW64 contexts plus opt-in `MADEIRA_FEX_X87_EXACT_INT64=1` 64-bit integer provenance (`FILD`/`FISTP m64`) from `thebcd69/bcd-fex` (appending fields in `CpuStateFrame` after `IosBlockRing` so existing frame offsets do not shift). |

A patch must apply on the current FEX pin. When the pin moves, rebase the
patches onto it (or drop a patch the new pin already covers).
