# Madeira's Wine patches

Changes to Wine (the `wine` submodule) that live in this repository until
they are in Wine's own repository. `apply.sh` applies them, in file-name
order, to the `wine` working tree before `tools/build/build-wine.sh`,
`build/wine-i386/build.sh`, `build/ntdll-unix/build.sh`,
`build/win32u-unix/build.sh`, and `build/wineserver/build.sh` build Wine;
it skips a patch that is already applied, and `apply.sh --revert` takes them
out. The `wine` submodule pin does not change.

| Patch | What it fixes |
|---|---|
| `0001-bcd-wine-core-correctness-and-perf.patch` | Ports core Wine fixes from `thebcd69/bcd-games` and `thebcd69/bcd-wine`: single-list xattr lookup (`MADEIRA_XATTR_ONE_LIST=0` opts out), `GLOBALROOT` DOS path resolution, statfs free-space fallback and plain-fd pipe state in `ntdll/unix/file.c`, `NtQueryInformationToken` bounds fix, opt-in kernel-APC sleep (`MADEIRA_SLEEP_KERNEL_APC=1`), `RtlWaitOnAddress` wake ordering (`__i386__`) and opt-in recheck (`MADEIRA_WOA_RECHECK=1`), `getsockopt`/`/dev/urandom` RWX buffer EFAULT bounce and inverse-DST timezone caching fixes in `ntdll/unix`, direct `time()` in `msvcrt`, `D3DXCreateVolumeTextureFromResourceEx`, `dinput` cdecl callback wrappers, opt-in `xaudio2_7` callback order (`MADEIRA_XAUDIO2_CALLBACK_ORDER=1`), `combase` implicit MTA creation, `setupapi` `devinst_table` SRW lock, `win32u` `NtGdiEnumFonts` face-name clamp, `shell32` explorer navpane null guard, and `wow64` null-SID token guard. |
| `0002-bcd-wine-vkd3d-hlsl-and-fx-fixes.patch` | Ports `vkd3d-shader` fixes from `thebcd69/bcd-games` and `thebcd69/bcd-wine`: fresh compile state per effect shader (`fx_2_0`/`fx_4_0`/`fx_5_0`, `MADEIRA_FX_WRITER=0` opts out), `point` and geometry/interpolation keywords allowed as HLSL identifiers unless followed by a type/modifier, and target-qualified `register(ps/vs/..., c#)` reservations. |

A patch must apply on the current `wine` pin (on top of `patches/wine-opengl-winios.patch`).
When the pin moves, rebase the patches onto it (or drop a patch the new pin already covers).
