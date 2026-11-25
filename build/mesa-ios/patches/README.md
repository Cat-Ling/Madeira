# Mesa patches

Numbered patches (`0001-...` to `0008-...`) are for the OSMesa + Zink build of Mesa 25.0.7
(`build/mesa-ios/build.sh`). Patches named `kosmickrisp-ios-*` are for the KosmicKrisp Vulkan
driver build of Mesa 26.3.1 (`build/mesa-ios/build-kosmickrisp.sh`, `docs/KOSMICKRISP.md`). Each
script applies only its own set. All patches change Mesa code and are offered under Mesa's
licence (MIT).

- `0008-zink-moltenvk-zero-unwritten-fs-inputs.patch`: Metal refuses a fragment input that the
  vertex shader does not output at the same location, component and type. At program link
  (MoltenVK only), the vertex stage first stores zero into every varying component the fragment
  shader reads, and both stages get one variable per slot with the same shape.
  `MADEIRA_ZINK_LINK_FS_INPUTS=0` turns this off, and `=1` turns it on for other drivers.
- `0009-osmesa-allow-compressed-fallback.patch`: Metal on A-series iPhones and iPads has no BC
  texture sampling (`supportsBCTextureCompression = NO`), so MoltenVK and KosmicKrisp report no BC
  formats. Mesa can still expose S3TC (DXT1/3/5), RGTC, LATC and BPTC and decode those uploads to
  RGBA8 on the CPU, but only when `allow_compressed_fallback` is on. The DRI frontends take it from
  driconf, where it defaults to true. OSMesa never reads driconf and left it false, so those
  extensions were missing, a game that uploads DXT data without checking got `GL_INVALID_ENUM`, and
  the incomplete texture sampled as opaque black (Mewgenics, #566). OSMesa now turns the
  option on; a GPU with BC keeps the native formats. `MADEIRA_GL_COMPRESSED_FALLBACK=0` turns it
  off.
- `kosmickrisp-ios-0001-wsi-metal-no-display-sync-on-ios.patch`: the Metal WSI sets
  `CAMetalLayer.displaySyncEnabled`, which iOS does not have. On iOS it is skipped, so an
  immediate-mode swapchain presents with vsync.
- `kosmickrisp-ios-0002-link-system-frameworks.patch`: links Foundation, CoreGraphics and libobjc
  into `libvulkan_kosmickrisp.dylib`. Upstream relies on `-undefined dynamic_lookup` for them. With
  the patch, only the driver's weak, unimplemented entry points are looked up at load time, and
  those resolve to NULL.
- `kosmickrisp-ios-0003-export-get-proc-addr-on-apple.patch`: on Apple platforms the driver also
  exports `vkGetInstanceProcAddr` and `vkGetDeviceProcAddr`. An app can then `dlopen` it and use it
  as its libvulkan without a Vulkan loader, the same way it uses MoltenVK.
- `kosmickrisp-ios-0004-metal4-drawable-sync.patch`: Mesa 26.3.1 upstreamed Metal 4 drawable
  synchronisation (`waitForDrawable:`/`signalDrawable:` and releasing submitted/destroyed drawables),
  while `wsi_metal_layer_{make,remove}_queue_resident` only compiled on macOS 26. This patch enables
  the iOS 26 residency-set path so `CAMetalLayer` drawables are resident on the queue on iOS, and
  releases any overwritten `cmd->drawable` if a command buffer is re-recorded before submission.
