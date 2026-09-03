# OMARec

A fully self-contained [Omarchy](https://omarchy.org) bar-widget plugin that shows a
**floating live webcam overlay** — the same idea as `omarchy screenrecord --with-webcam`,
minus the recording — with user-configurable **size**, **orientation**
(portrait/landscape) and **corner rounding**.

It adds a camera glyph to the bar. Click it to open a panel where you can toggle the
overlay, pick which webcam to remember, and tune the size / orientation / rounding.

## What it does

- Toggles a floating, always-on-top camera preview (bottom-right corner by default).
- Lets you choose which webcam to use, its size (small/medium/large), its orientation
  (portrait 8:9 or landscape 16:9), and its corner rounding (0/8/16/24 px).
- Uses its **own Wayland app id** (`omarec-<orientation>-<size>-r<rounding>`) and applies
  its own geometry via a runtime `hl.window_rule` — so it needs **zero changes** to
  `hyprland.lua` or any Omarchy config, and it **never collides with or leaks into**
  Omarchy's screen-recording `WebcamOverlay`.

## Install / enable

1. Put this folder at `~/.config/omarchy/plugins/omarec/`
   (or the community-plugins directory used by your Omarchy setup).
2. Restart the shell, or it is picked up on reload.
3. Add the widget to the bar, e.g. in `~/.config/omarchy/shell.json`:

   ```json
   "right": [ { "id": "omarec" } ]
   ```

## CLI

Backed by `bin/omarec` (also callable on its own):

```sh
omarec                      # toggle
omarec on                   # start overlay
omarec off                  # stop overlay
omarec resize S             # small | medium | large | smaller | larger
omarec orientation O        # portrait | landscape
omarec rounding PX          # 0..30 corner radius in pixels
omarec devices              # list webcams
omarec pick-device          # choose & remember a webcam
omarec status               # running | stopped
omarec get-size|get-orientation|get-rounding|get-device
```

Preferences (remembered camera, size, orientation, rounding) are stored in
`omarec.conf` **inside** this plugin folder, so the plugin owns all of its state.

## Panel & controls

The widget uses Omarchy's native panel kit (`qs.Ui`): a `Panel` bar-widget with a
`PanelHero` (toggle switch), an action row (Camera on/off, Pick camera), and sectioned
rows for camera, size, orientation and rounding — styled identically to Omarchy's other
panels.

- **Left-click** the bar icon to open/close the panel.
- **Right-click** the bar icon to toggle the overlay.
- The bar glyph shows a **LIVE** pill with a faint FPV shake while the overlay is up.
- In the panel, navigate with arrow keys and activate with Enter; the mouse works too.
  (There are no keyboard shortcuts — control is via the bar, the panel, or the CLI.)

The plugin is split like first-party plugins: `Service.qml` (one headless instance
owning all processes/timers/IPC — the `omarec` IPC target: `on`, `off`, `toggle`,
`open`, `close`, `refresh`, `status`, `pickDevice`, `orientation`, `rounding`,
`setOrientation`, `setRounding`) and `BarWidget.qml`
(a view per monitor rendering the panel).

## Performance

The service polls only a single cheap `status` probe on a generous timer (3s). Camera,
size, orientation and rounding labels refresh lazily — when the panel opens or an action
lands — so idle CPU stays near zero and only one process is spawned per tick.

## Isolation

- **Zero edits to Omarchy defaults.** `hyprland.lua`, `shell.qml`, etc. are never
  touched. Rather than reusing Omarchy's `WebcamOverlay` rules, the plugin owns its
  overlay geometry through its own app id and a runtime `hl.window_rule`, so nothing it
  does affects Omarchy's own screen-recording overlay (and vice-versa).
- **Self-contained state.** The only file the plugin writes is `omarec.conf` inside
  its own folder (camera + size + orientation + rounding). No files are written to
  `/tmp`, the runtime dir, or Omarchy's config dir.
- **Does not own shared resources.** It never records, and it stops its own mpv
  instance only — it does not kill or modify any other process's state.

## Lightweight

The service is a thin QtObject. Idle it spawns a single cheap `status` probe every 3s
and nothing else; the lazy labels refresh only when the panel opens or an action lands.
The QML is static (no animations), so shell CPU/memory cost is negligible. The only
notable consumer is `mpv` itself, and that is only running while the overlay is up.

## Uninstall

Delete this `omarec` folder and remove the `omarec` entry from `shell.json`:
that removes the plugin **and** its entire state, since everything lives in the folder.
Nothing in Hyprland or Omarchy is ever modified, so there is nothing to revert.
