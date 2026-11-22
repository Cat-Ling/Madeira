# vkd3d-proton patches

Applied in numeric order by `build/vkd3d-proton/build.sh` (`patch -p1`) to upstream
vkd3d-proton `750061ae2be846d19d6364628eaf5ea4beb8e619`. Patches `0001`–`0003` come
from NutsEmu 0.0.1 build 1382 and `0004`–`0010` come from NutsEmu 0.0.1 build 1977
(Evan Bolton, published corresponding source, `patches/vkd3d-proton/`),
LGPL-2.1-or-later like vkd3d-proton. Each file's header keeps the origin and the
dates NutsEmu gives; `0004` additionally enables the Windows TLS slot path whenever
`_WIN32` is defined so Madeira's ARM64EC cross-build gets the fix without defining
`WINE_TEB_TSD_SLOT`.

| Patch | First added (NutsEmu) | Summary |
|---|---|---|
| 0001-transform-feedback-and-texel-alignment-optional.patch | 2026-10-05 | No transform feedback or single-texel alignment: a warning instead of a device-creation failure (stream output then unavailable) |
| 0002-no-layered-api-properties.patch | 2026-10-05 | The VK_KHR_maintenance7 layered-API properties chain is not queried (winevulkan faulted converting it back) |
| 0003-kosmickrisp-shader-model-gates.patch | 2026-10-06 | On VK_DRIVER_ID_MESA_KOSMICKRISP only: feature level 12_0 without tiled resources, shader model past 6.0 without float32 denormal control, the compute-derivatives fallback for 6.6; plus one INFO line with the feature-level inputs (every driver) |
| 0004-dxil-spirv-allocator-tls-without-x18.patch | 2026-10-16 | dxil-spirv: keep `ChainAllocator` in a Windows TLS slot (`TlsAlloc`/`TlsGetValue`/`TlsSetValue`) instead of compiler `thread_local` `x18` accesses |
| 0005-placed-buffers-at-buffer-alignment.patch | 2026-10-21 | Allow placed buffers at `VKD3D_MIN_BUFFER_ALIGNMENT` (256 bytes) instead of failing with `E_INVALIDARG` off 64 KB alignment |
| 0006-big-gpu-allocations-logged.patch | 2026-10-21 | Log D3D12 heaps >= 32 MB and committed/placed resources >= 32 MB or >= 8M texels (up to 400 lines) |
| 0007-swap-chain-at-the-back-buffer-size-for-metalfx.patch | 2026-11-20 | Keep Vulkan swapchain extent at the smaller back-buffer size when `DXMT_METALFX_SPATIAL_SWAPCHAIN=1` |
| 0008-kosmickrisp-small-occlusion-query-pools.patch | 2026-11-20 | Use 256-query occlusion pools on KosmicKrisp to avoid exhausting its 32,768-slot visibility table |
| 0009-kosmickrisp-pipelines-match-bound-unused-color-attachments.patch | 2026-11-20 | Compile and cache RTV-matching variants for colorless pipelines on KosmicKrisp without `EXT_dynamic_rendering_unused_attachments` |
| 0010-kosmickrisp-gpu-addresses-use-aligned-padding.patch | 2026-11-20 | Treat KosmicKrisp like Turnip in `d3d12_device_aligns_bda_64k()` so 64 KiB GPU address alignment uses padded allocations |
