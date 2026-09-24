# Changelog

## 0.6.0

### Interface

- Compact home page with battery rows, circular sound-mode controls, contextual ANC/transparency settings, and Sound Effects.
- Advanced Settings groups audio quality, connections, earbud controls, preferences, preset management, and device information.
- Theme-aware earbud and listening-mode icons; Back restores the parent page's scroll position.
- Right-click cycles saved bar display modes: icon only, lowest battery percentage, or three individual battery indicators.
- Device picker for multiple devices and recovery of a missing preferred device.

### Device features

- LDAC control with fresh readback verification and separate computer playback codec status.
- Auto power-off, touch tones, low-battery prompt, and high-volume limits where supported.
- Left/right button mapping and confirmed reset to device defaults.
- Firmware, serial number, earbud connection, and adaptive ANC information.
- Saved EQ preset clipboard import/export with validation and overwrite confirmation.

### Reliability

- Preserve Spatial Audio when an attempted LDAC enable fails.
- Treat missing LDAC readback as unknown rather than successful disable.
- Keep keyboard navigation targets visible in scrolling pages.
- Retain compatibility with the older `showBatteryPercent` preference until a bar display mode is saved.

LDAC may require a firmware update through the Soundcore Android app. Earbud capabilities vary by model; hardware verification was performed with R60i NC firmware 04.89.
