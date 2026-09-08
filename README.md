<h1 align="center">Omacore</h1>

<p align="center">
  Soundcore earbuds in the <a href="https://omarchy.org">Omarchy</a> bar: battery for each earbud and the case, ambient sound mode (Noise Cancelling / Transparency / Normal) with its own per-mode ANC settings, and Sound Effects, drawn in Omarchy's own panel idiom.
</p>

<p align="center">
  The <a href="https://omarchyplugins.com/plugin.html?id=io.github.thisisgm.omapods">omapods</a> plugin does this for AirPods. Omacore is the same idea for Soundcore.
</p>

<p align="center">
  <img src="screenshots/omacore.png" alt="Omacore panel showing the Soundcore R60i NC battery, sound mode, ANC settings and sound effects from the Omarchy bar" width="360">
</p>

## How it looks

Click the Omacore icon (right side of the bar) to open the panel above —
see **What it shows** below for what's in it.

## Install

Your earbuds must be paired over Bluetooth (`omarchy bluetooth device` or
the stock Bluetooth panel) and registered with OpenSCQ30 (step 2 of
**Setup** below). Then:

```bash
omarchy plugin add https://github.com/birajdotdev/omacore.git --enable
```

That's it. The widget auto-detects whichever Soundcore device is currently
connected over Bluetooth — no MAC address to configure.

If `openscq30` isn't on `PATH` yet, the bar icon shows in the alert color and
the panel offers an **Install OpenSCQ30 CLI** button (or press `i`) — this
opens the bundled `omacore-install` in a terminal and drops the official
binary into `~/.local/bin`, no sudo needed. You still have to register the
device with OpenSCQ30 afterwards (see **Setup**), but the CLI install itself
is now a click away.

## What it shows

- **Which earbuds** — the panel title shows the friendly Bluetooth device
  name (e.g. "Soundcore R60i NC") that the discovery script finds, not a
  generic "Soundcore".
- **Battery** for the left earbud, the right earbud and the case. Soundcore's
  hardware only reports ten discrete steps, so the widget shows a rounded
  percent rather than a raw sensor value.
- **Sound mode** — Noise Cancellation, Transparency or Normal — with the
  active mode checked, and one click or `n`/`t`/`o` to switch it. Selecting a
  mode reveals that mode's own settings below it, mirroring Soundcore's app:
  - **Noise Cancellation** shows an inline Mode dropdown (Manual / Adaptive /
    Multi-Scene) plus a Real-time Adaptive ANC toggle — shown regardless of
    which of the three is selected, same as the Soundcore app:
    - **Manual** additionally shows a 1-5 intensity level.
    - **Multi-Scene** additionally shows a Transport / Outdoor / Indoor
      picker as three side-by-side buttons.
    - **Wind noise suppression** — a toggle, one click or `w` (while in
      Noise Cancellation) to flip it.
  - **Transparency** shows a Fully Transparent / Vocal Mode picker.
  - **Normal** shows none of the above — only Sound Effects, below.
- **Sound Effects** (Soundcore's spatial audio) — Music / Movie / Gaming as
  three side-by-side buttons, always shown regardless of sound mode.

All of the above are only shown when openscq30 reports the setting at all
(model and firmware dependent — confirmed present on the R60i NC / P31i).
OpenSCQ30 exposes still more per-device settings (button remapping, EQ,
dual connections, …) — run `openscq30 device -a <mac> list-settings --json`
to see everything your earbuds support, and extend
`Model.js`/`Service.qml`/`Panel.qml` the same way the rest is wired if you
want more of it in the bar.

## How it works

Unlike [omapods](https://github.com/thisisgm/omarchy-pods) (AirPods, which
speaks Apple's own BLE protocol via a background daemon), there is no
background daemon here. [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30)'s
CLI opens a fresh Bluetooth connection on every invocation, so this widget
**polls** — the bundled `omacore-status` script discovers whichever paired
Soundcore device is currently connected over Bluetooth (cross-referencing
`bluetoothctl devices Connected` with OpenSCQ30's `paired-devices list`),
reads the device's capability schema via `list-settings --json`, then fetches
the current value of every relevant setting. The wrapper script `omacore-set`
writes a setting back. No MAC address needs to be configured anywhere —
discovery is automatic on every poll.

## Requirements

- **[OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30)'s CLI**, `openscq30`,
  on `PATH`. It is free/open-source (GPL-3.0-or-later) and not written by or
  affiliated with this plugin's author — it just happens to be the CLI this
  widget shells out to.

  **Version matters for newer devices.** R60i NC / P31i support landed in
  OpenSCQ30 v2.10.0. The `openscq30-cli-bin` AUR package may lag behind
  (it was pinned to v2.7.0 at the time this was written) — if
  `openscq30 list-models` doesn't list your `Soundcore...` id, skip the AUR
  package and grab the official binary release instead, linking it onto
  `PATH`:

  ```bash
  mkdir -p ~/.local/opt/openscq30
  gh release download v2.12.0 -R Oppzippy/OpenSCQ30 \
    -p 'openscq30-cli-linux-x86_64' -D ~/.local/opt/openscq30
  chmod +x ~/.local/opt/openscq30/openscq30-cli-linux-x86_64
  ln -sf ~/.local/opt/openscq30/openscq30-cli-linux-x86_64 ~/.local/bin/openscq30
  ```

  (Substitute the latest release tag for `v2.12.0` if a newer one exists.)

- Earbuds paired over the normal Bluetooth flow first (`omarchy bluetooth
  device` or the stock Bluetooth panel).

## Setup

The plugin itself needs no configuration once installed. The only prerequisite
is that your earbuds are paired over Bluetooth **and** registered with
OpenSCQ30 (OpenSCQ30 keeps its own small database mapping MAC address →
model, separate from BlueZ's pairing):

1. Install `openscq30` (above, picking whichever path gets you a build new
   enough for your model) and pair your earbuds over Bluetooth as usual.

2. Register the device with OpenSCQ30:

   ```bash
   openscq30 paired-devices add -a AA:BB:CC:DD:EE:FF -m SoundcoreD1202C
   ```

   Use `SoundcoreD1202C` for the **R60i NC**, `SoundcoreD1202` for the
   **P31i**. Run `openscq30 list-models` to see every supported model id —
   the exact id string (and whether it's prefixed `Soundcore...`) has
   changed between OpenSCQ30 versions, so trust `list-models` over any id
   written down here.

Once the device is paired and now `openscq30 paired-devices add`-registered,
the widget finds it automatically whenever it's connected over Bluetooth.

## Update / Remove

```bash
omarchy plugin update io.github.birajdotdev.omacore
omarchy plugin remove io.github.birajdotdev.omacore
```

`openscq30` and its paired-device database are untouched — remove them
separately with your AUR helper and `openscq30 paired-devices remove -a
<mac>` if you no longer want them.

## Keyboard

| Key | Action |
|-----|--------|
| `j` / `k`, `↓` / `↑` | move between rows |
| `←` / `→` | adjust the Manual ANC level, when it's the focused row |
| `enter` / `space` | activate the current row |
| `n` | Noise Cancellation |
| `t` | Transparency |
| `o` | Normal |
| `w` | toggle wind noise suppression (while in Noise Cancellation, if supported) |
| `r` | refresh |
| `tab` | move to the next panel |
| `esc` | close |

Every other setting (scene, transparency mode, sound effect) is reached by
moving the cursor to its row and pressing `enter`/`space`, or by clicking it
directly. The ANC Mode dropdown works the same way to open it; once open, its
own `j`/`k`/`↓`/`↑` and `enter` pick an option and `esc` closes it without
closing the panel. For a toggle row (wind noise suppression, real-time
adaptive ANC), a mouse click only registers on the switch itself, not the
row's label — keyboard `enter`/`space` on the row still works either way.

Left click opens the panel.

## Settings

| Setting | Default | Notes |
|---------|---------|-------|
| Poll interval (seconds) | 30 | How often the widget re-runs `omacore-status`. |
| Hide when unreachable | on | Leaves the bar entirely rather than sitting there with nothing to say. Kept visible (in the alert color) when the issue is a missing `openscq30` CLI rather than unreachable earbuds, so the install button stays reachable. |
| Desktop notifications | on | Notifies on disconnect and when a bud/case battery drops to 20% or below (once per drop, via `omarchy-notification-send`). |

## Credits

The hard part is not this panel. It is
[OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30) by **Oppzippy**, which
reverse-engineered Soundcore's BLE/RFCOMM control protocol across dozens of
devices. This panel only shells out to its CLI and draws what comes back.

## Licence

MIT. See [LICENSE](LICENSE). This plugin vendors no OpenSCQ30 code — it only
invokes the separately-installed `openscq30` binary, which is GPL-3.0-or-later
under its own project.
