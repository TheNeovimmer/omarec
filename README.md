# OMARec Studio

A polished, fully self-contained [Omarchy](https://omarchy.org) bar-widget plugin for
sharing your screen in meetings with a **floating live webcam overlay**. It provides the
presence of a screen-recording camera bubble, without recording anything.

It adds a dedicated video-camera icon to the bar. Click it to open a focused Studio panel
where you can start the overlay, pick a webcam, and tune its size, framing, rounding, and
screen position. Every setting is remembered inside the plugin.

## What it does

- Toggles a floating, always-on-top camera preview (bottom-right by default).
- Lets you choose which webcam to use, the overlay size (small/medium/large), framing
  (portrait 8:9 or landscape 16:9), corner rounding (0/8/16/20 px), and any screen corner.
- Restarts the overlay safely when you change a visual setting, so the new result is shown
  immediately instead of waiting for the next meeting.
- Uses its **own Wayland app id** (`omarec-<orientation>-<size>-r<rounding>-<position>`) and applies
  its own geometry via a runtime `hl.window_rule` — so it needs **zero changes** to
  `hyprland.lua` or any Omarchy config, and it **never collides with or leaks into**
  Omarchy's screen-recording `WebcamOverlay`.

## Install, enable, and remove

For a git-hosted copy, Omarchy installs and enables it in one command:

```sh
omarchy plugin add <plugin-git-url> --enable --yes
```

For this local checkout, validate it, then enable it in the right side of the bar:

```sh
omarchy plugin validate ~/.config/omarchy/plugins/omarec
omarchy plugin enable omarec right
```

To remove it completely, turn off the overlay and let Omarchy remove the plugin:

```sh
~/.config/omarchy/plugins/omarec/bin/omarec off
omarchy plugin remove omarec --yes
```

There are no system configuration changes to undo. Removing the plugin also removes its
saved camera settings because its state file lives in the plugin directory.

## CLI

Backed by `bin/omarec` (also callable on its own):

```sh
omarec                      # toggle
omarec on                   # start overlay
omarec off                  # stop overlay
omarec resize S             # small | medium | large | smaller | larger | reset
omarec smaller | larger     # step the size down / up
omarec orientation O        # portrait | landscape
omarec rounding PX          # 0..20 corner radius in pixels
omarec position CORNER      # top-left | top-right | bottom-left | bottom-right
omarec devices              # list webcams
omarec pick-device          # choose & remember a webcam
omarec status               # running | stopped
omarec get-size|get-orientation|get-rounding|get-position|get-device
omarec get-all [--json]     # all settings + status in one call
omarec check                # dependency + device + status diagnostics
omarec reset                # restore default size/orientation/rounding/position
omarec help | version
```

Preferences (remembered camera, size, orientation, rounding, and position) are stored in
`omarec.conf` **inside** this plugin folder, so the plugin owns all of its state.

## Panel & controls

The widget uses Omarchy's native panel kit (`qs.Ui`) with a concise Studio header, a live
state toggle, direct camera selection, and grouped controls for overlay size, orientation,
rounding, and screen position. It feels native to Omarchy while keeping meeting controls
visible at a glance.

- **Left-click** the bar icon to open/close the panel.
- **Right-click** the bar icon to toggle the overlay.
- The bar icon becomes a clear **LIVE** pill while the overlay is up (it hides
  with the panel closed when `showWhenIdle` is off).
- In the panel, navigate with arrow keys and activate with Enter; the mouse works too.
  (There are no keyboard shortcuts — control is via the bar, the panel, or the CLI.)
- The panel has a **Reset to defaults** row restoring
  medium / portrait / 12px / bottom-right.

The plugin is split like first-party plugins: `Service.qml` (one headless instance
owning all processes/timers/IPC — the `omarec` IPC target: `on`, `off`, `toggle`,
`open`, `close`, `refresh`, `status`, `size`, `setSize`, `device`, `pickDevice`,
`orientation`, `setOrientation`, `rounding`, `setRounding`, `position`,
`setPosition`, `reset`) and `BarWidget.qml`
(a view per monitor rendering the panel).

## Performance

The service polls only a single cheap `status` probe on a generous timer (3s).
Camera and overlay settings refresh lazily in **one** `get-all --json` call —
when the panel opens, an action lands, or `omarec.conf` changes on disk — so
idle CPU stays near zero and only one process is spawned per tick. Rapid bar
clicks are serialised with last-intent-wins instead of stacking overlay
restarts.

## Isolation and privacy

- **Zero edits to Omarchy defaults.** `hyprland.lua`, `shell.qml`, etc. are never
  touched. Rather than reusing Omarchy's `WebcamOverlay` rules, the plugin owns its
  overlay geometry through its own app id and a runtime `hl.window_rule`, so nothing it
  does affects Omarchy's own screen-recording overlay (and vice-versa).
- **Self-contained state.** The only file the plugin writes is `omarec.conf` inside
  its own folder (camera + size + orientation + rounding + position). No files are written to
  `/tmp`, the runtime dir, or Omarchy's config dir.
- **Does not own shared resources.** It never records, and it stops only the mpv process
  carrying OMARec's private Wayland app-id — other webcam previews and Omarchy's recorder
  overlay are left alone.

## Lightweight

The service is a thin QtObject. Idle it spawns a single cheap `status` probe every 3s
and nothing else; the lazy labels refresh in one `get-all --json` call only when the
panel opens, an action lands, or the conf file changes.
The QML is static (no animations), so shell CPU/memory cost is negligible. The only
notable consumer is `mpv` itself, and that is only running while the overlay is up.

## Troubleshooting

```sh
omarec check    # deps, remembered settings, visible webcams
omarec devices  # what the picker would offer
```

- **"No webcam devices found"**: no capture-capable `/dev/video*` exists.
  Check `v4l2-ctl --list-devices` and your USB connection.
- **Overlay fails to appear**: run `omarec on` in a terminal — a missing
  `mpv`/`jq`/`hyprctl` prints a direct error, and `check` lists gaps.
- **Stale panel values**: the service re-reads `omarec.conf` on every change,
  including edits made from the terminal. `omarchy shell omarec refresh`
  forces a re-read.
- **Tests**: `tests/run.sh` exercises the CLI contract (validation, clamping,
  `get-all --json`, `check`) without needing a camera.

## Uninstall

Delete this `omarec` folder and remove the `omarec` entry from `shell.json`:
that removes the plugin **and** its entire state, since everything lives in the folder.
Nothing in Hyprland or Omarchy is ever modified, so there is nothing to revert.
