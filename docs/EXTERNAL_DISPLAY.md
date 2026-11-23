# External Display Console Mode & Companion Deck

When an external display is connected (AirPlay or wired HDMI/USB-C), direct
game sessions (`MADEIRA_DESKTOP != 1`) and the launcher switch into **TV Console
Mode** (`app/Madeira/ExternalDisplayConsole.swift`), separating the 10-foot TV
output from the iPhone/iPad screen.

## How the two screens work

- **External display (`ExternalDisplay` & `ExternalDisplayRootView`):**
  - **Before play:** renders a 10-foot Gaming Console launcher (`Games`,
    `Display & TV`, `Controls`, `Settings`) with full-bleed backdrop art, cover
    shelf navigation, per-game setup, and live aspect/overscan preview.
  - **During play:** presents only the pure `MetalHostView` game surface inside
    `ExternalDisplayLayout.rect(...)` (no cluttered HUD), with optional
    temporary overscan calibration guides while adjusting margins. An optional
    minimal corner FPS badge is **off** by default.
  - **Pause menu:** pressing `Back + Start` on a controller or `F10` on a
    hardware keyboard opens the translucent TV Pause Menu directly on the TV.
- **Phone / iPad Companion Deck (`ExternalPhoneCompanionView`):**
  - Keeps full performance telemetry (`LibraryMetrics`, `FrameTimeGraph`, and
    toggleable `LibraryLiveLogs`) on the phone screen while the TV stays clean.
  - Offers touch controls for scaling (`Fit`, `Fill`, `Stretch`, `Aspect`),
    aspect ratio override (`Auto`, `16:9`, `16:10`, `4:3`, `21:9`, `32:9`),
    overscan margin (`0–10%`), FPS cap, Eco mode, and switching between
    **Companion Deck**, **Phone Touchpad**, and **Touch Controls**.
- **Desktop sessions (`MADEIRA_DESKTOP = 1`):** stay on standard iOS screen
  mirroring so compositor touch mapping keeps working inside the device window.

## Input isolation & AoL readiness

- While the TV Console launcher or TV Pause Menu is active
  (`ExternalDisplay.shared.consoleOwnsInput`), connected controllers, hardware
  keyboards, and mice control only the TV Console (never leaking into phone UI).
- While playing on the TV in **Companion Deck** mode, phone touches interact
  only with the Companion Deck and never click or steal hardware mouse/keyboard
  focus from the game on the TV.
- `ExternalDisplay.RemoteAccessorySnapshot` and `ExternalConsoleController`
  expose unified injection and status hooks ready for **Accessories Over LAN
  (AoL)** alongside local USB/Bluetooth accessories.

## Logs and switches

- Logs `[display] external console on: WxH (native PxQ) @FPSHz` / `off` and
  `[display] apply ... ext=1/0`.
- Set `env.MADEIRA_EXTERNAL_DISPLAY = 0` in `Documents/madeira.cfg` (or toggle
  **Dedicated TV Console** in the library banner / TV Settings / Pause Menu) to
  disable the dedicated external view and use standard screen mirroring.
