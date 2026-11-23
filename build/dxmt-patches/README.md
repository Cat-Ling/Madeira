# Madeira's DXMT patches

Changes to DXMT (the `dxmt` submodule) that live in this repository until
they are in DXMT's own repository. `apply.sh` applies them, in file-name
order, to the `dxmt` working tree before `build/dxmt-ios/build.sh` (the
native Direct3D 9 frontend in `libdxmt_combined.a`),
`build/wine-i386/build.sh` (the 32-bit DLLs) and
`build/windows-runtime/build.sh` (the 64-bit DLLs) build DXMT; it skips a
patch that is already applied, and `apply.sh --revert` takes them out. The
`dxmt` submodule pin does not change.

| Patch | What it fixes |
|---|---|
| `0001-d3d9-index-range-per-draw.patch` | A 32-bit Direct3D 9 indexed draw copies only the index bytes it reads, instead of the whole index buffer before every draw after a lock (Call of Duty: Black Ops drew at 2 to 20 FPS). `env.MADEIRA_D3D9_INDEX_RANGE = 0` goes back to the whole copy. Checked by `tests/host/check-d3d9-index-range.py` |
| `0002-d3d9-fullscreen-extents-and-refresh.patch` | Fullscreen D3D9 `CreateDevice` / `Reset` matches adapter modes by width and height regardless of `FullScreen_RefreshRateInHz` (fixing 30/50/59/75/120 Hz requests on synthetic 60 Hz virtual monitor modes like Fit resolutions) and accepts all 37 standard PC extents plus 320x240 and 512x384 in `kPresentableExtents`. |
| `0003-d3d9-const-extent-vbuf-bounds-and-dxso-agx-safety.patch` | Sizes non-relative D3D9 float constant uploads to at least the shader's highest static register (keying the constant cache on extent), subtracts stream `OffsetInBytes` from `VbufEntry::length`, denies `D3DUSAGE_QUERY_POSTPIXELSHADER_BLENDING` on 32-bit float formats, enables byte-aligned vertex fetches and IEEE `min`/`max` in DXSO, and bumps `kD9ShaderCacheEpoch`. |
| `0004-bcd-d3d9-dxso-presenter-and-ps-clamp.patch` | Ports D3D9/DXSO/presenter fixes from `thebcd69/bcd-games` and `thebcd69/bcd-dxmt`: emits SM 3.0 VS outputs (`NORMAL`, `TANGENT`, `BINORMAL`, `BLENDWEIGHT`, `BLENDINDICES`, `DEPTH`), emits `[[point_size]]` only for point draws, unpacks `D3DDECLTYPE_DEC3N` and `UDEC3`, maps non-layer backbuffer formats to `BGRA8Unorm` in `CAMetalLayer`, makes luminance RTs opt-in (`MADEIRA_D3D9_LUMINANCE_RT=1`), resets cross-device late readback signals, adds D3D9 stuck-query diagnostics (`DXMT_D9_QUERY_LOST_MS`) and texture format logging, adds opt-in `MADEIRA_PS_CLAMP=1/2` with cache salting for DXBC and DXSO, and bumps `kD9ShaderCacheEpoch` to 13. |
| `0005-bcd-d3d10-d3d11-dxgi-and-winemetal-fixes.patch` | Ports D3D10/D3D11/DXGI/winemetal fixes from `thebcd69/bcd-games` and `thebcd69/bcd-dxmt`: skips draws after failed tessellation/GS mesh PSO compilation, handles non-position GS `dcl_input_siv` and `vGSInstanceID`, implements `IDXGISwapChain1::SetRotation`/`GetRotation` identity, guards null `CopyStructureCount` and staging `UpdateSubresource`, enforces D3D11 and Metal texture size limits, resizes tiny fullscreen WSI windows, adds opt-in `MADEIRA_VIEW_PRIVATE_REF`, `MADEIRA_BUFFER_RTV_EMPTY`, and `DXMT_MODE_LIST_ANY_BPP`, fixes `d3d10` `IAGetIndexBuffer` / `DrawIndexedInstanced` arguments, and clamps sampler anisotropy (`1..16`). |
| `0006-bcd-winemetal-safety-and-diagnostics.patch` | Ports Tier 3 winemetal safety, diagnostics, and opt-in placement-heap fixes from `thebcd69/bcd-games`: weak-imports `MTLSetShaderCachePath`/`MTLGetShaderCachePath` in `cache.c`, gates `MADEIRA_FRAMEGEN` on `@available(iOS 26.0, macOS 26.0, *)`, refuses impossible texture dimensions before Metal `SIGABRT` (`[mtl-tex-fail]`), logs `[gpu-error]` diagnostics on failed command buffers, and adds opt-in `madeira.cfg heap-untracked = 1` for placement heaps. |

A patch must apply on the current `dxmt` pin. When the pin moves, rebase the
patches onto it (or drop a patch the new pin already covers).
