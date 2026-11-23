# External display and AirPlay

Direct game sessions (`MADEIRA_DESKTOP != 1`) move their `MetalHostView` to a
connected external display (AirPlay second screen or wired HDMI/USB-C) when one
is present, leaving touch controls, the session menu, and game-mode GDI launcher
dialogs on the device screen.

## What moves and what stays

- **Moves to the external display (`ExternalDisplay` in `app/Madeira/ContentView.swift`):**
  the window-hosted `CAMetalLayer` (`MetalHostView.shared`), sized into the
  external `UIWindow` using the session's `DisplayMode` (`Fit`, `Fill`, `Stretch`,
  or `Aspect`) and updated to the external screen's `maximumFramesPerSecond`.
- **Stays on the device:** touch controls (`ControlsWindow`), the session menu,
  the library HUD, touch/trackpad input mapping on `MetalBackedView`, and the
  game-mode GDI overlay (`Winios.m`), with a non-interactive `"Playing on
  external display"` label shown in place of the game surface.
- **Desktop sessions (`MADEIRA_DESKTOP = 1`):** deliberately stay on iOS
  screen mirroring. Desktop touch mapping relies on `Winios.m`'s compositor
  frame inside the device window, so the desktop compositor is not moved to an
  external `UIWindow`.

## Logs and rollback

- Connection and disconnection log `[display] external display on: WxH @FPSHz`
  and `[display] external display off`, and layout passes include `ext=1` or
  `ext=0`.
- Set `env.MADEIRA_EXTERNAL_DISPLAY = 0` in `Documents/madeira.cfg` to keep
  direct game sessions on the device screen (iOS mirroring only).
