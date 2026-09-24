pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Headless service for OMARec. One instance per shell process: it owns every
// Process, Timer and IPC handler in the plugin, and it is the only place that
// talks to bin/omarec. BarWidget.qml is instantiated once per monitor and only
// reads properties / calls functions declared here (reached via
// bar.shell.serviceFor(moduleName)).
//
// All mutation and all state reads go through the CLI, which is the same source
// the bar menu and keybinds use, so nothing can drift. The overlay uses its OWN
// Wayland app id (omarec-<orientation>-<size>-r<rounding>-<position>) with its
// own geometry applied via a runtime `hl.window_rule` — this plugin never
// touches hyprland.lua or any Omarchy config, and it never collides with
// Omarchy's own screen-recording `WebcamOverlay`.
QtObject {
  id: root

  // ------------------------------------------------------------- injected
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""

  // ------------------------------------------------------- public surface
  // The floating overlay is up when hyprctl sees one of our omarec-* windows.
  readonly property string state: _state
  readonly property bool active: _state === "running"
  // Remembered device and presets, resolved off the CLI so the panel and tooltip
  // agree with what bin/omarec will actually use.
  readonly property string camera: _camera
  readonly property string size: _size
  readonly property string orientation: _orientation
  readonly property string rounding: _rounding
  readonly property string position: _position
  // True while a picker menu is up; the panel can dim its Change button.
  readonly property bool picking: _picking
  // True when the CLI itself is unusable (missing deps); the panel shows
  // a hint instead of silently doing nothing.
  readonly property bool degraded: _degraded
  readonly property string degradedHint: _degradedHint
  readonly property bool busy: statusProc.running || settingsProc.running || actionProc.running || pickCameraProc.running

  // Resolved once: the plugin dir is wherever the shell loaded this file from.
  readonly property string pluginDir: {
    var value = String(Qt.resolvedUrl(".") || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    if (value.charAt(value.length - 1) !== "/") value += "/"
    return decodeURIComponent(value)
  }
  readonly property string cliPath: pluginDir + "bin/omarec"
  // Mirrors bin/omarec's own resolution order exactly, because the FileView
  // watcher has to land on the file the CLI actually writes: the XDG state
  // dir, never the plugin folder (writes there hot-reload the plugin and
  // would abort in-flight restarts).
  readonly property string confPath: {
    var stateHome = Quickshell.env("XDG_STATE_HOME")
    if (!stateHome) stateHome = (Quickshell.env("HOME") || "") + "/.local/state"
    return String(stateHome) + "/omarec/omarec.conf"
  }

  // -------------------------------------------------------------- private
  property string _state: "stopped"
  property string _camera: ""
  property string _size: "medium"
  property string _orientation: "portrait"
  property string _rounding: "12"
  property string _position: "bottom-right"
  property bool _picking: false
  property bool _degraded: false
  property string _degradedHint: ""
  // Latest action waiting while another one runs; only the newest is kept —
  // rapid clicks converge on the user's last intent instead of queueing stale
  // restarts of a camera overlay.
  property var _pendingArgs: null

  // When the overlay state changed since we last read it, nudge every widget
  // so the glyph/dot and panel stay in sync even while the panel is open.
  signal overlayChanged(bool active)

  // ------------------------------------------------------------ utilities
  function notify(message) {
    var base = root.omarchyPath || Quickshell.env("OMARCHY_PATH") || ""
    var binary = base !== "" ? base + "/bin/omarchy-notification-send" : "omarchy-notification-send"
    Quickshell.execDetached([binary, String(message)])
  }

  function applySettingsJson(text) {
    var data = null
    try {
      data = JSON.parse(String(text || ""))
    } catch (e) {
      return false
    }
    if (!data || typeof data !== "object") return false
    root._camera = String(data.device || "")
    root._size = String(data.size || "medium")
    root._orientation = String(data.orientation || "portrait")
    root._rounding = String(data.rounding || "12")
    root._position = String(data.position || "bottom-right")
    var next = String(data.status || "stopped") === "running" ? "running" : "stopped"
    var wasActive = root._state === "running"
    root._state = next
    if ((next === "running") !== wasActive) root.overlayChanged(next === "running")
    return true
  }

  // ---- status: is the overlay up? ----
  property Process statusProc: Process {
    id: statusProc
    command: [root.cliPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = text.trim() === "running"
        var wasActive = root._state === "running"
        root._state = next ? "running" : "stopped"
        if (next !== wasActive) root.overlayChanged(next)
      }
    }
  }

  // ---- remembered settings + status in one shot ----
  // A single `get-all --json` call replaces five one-value probes, so a full
  // refresh costs one process instead of five. It runs lazily (panel open,
  // action landed, conf changed) — the steady-state tick stays a single cheap
  // `status` probe.
  property Process settingsProc: Process {
    id: settingsProc
    command: [root.cliPath, "get-all", "--json"]
    stdout: StdioCollector {
      id: settingsOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: settingsErr
      waitForEnd: true
    }
    onExited: function(code) {
      if (code === 0 && root.applySettingsJson(settingsOut.text)) {
        root._degraded = false
        root._degradedHint = ""
      } else {
        // Only flag degraded when the CLI itself failed, not when there is
        // simply no webcam (that prints fine with an empty device).
        var err = String(settingsErr.text || "").trim()
        if (err !== "") {
          root._degraded = true
          root._degradedHint = err.split("\n")[0]
        }
      }
    }
  }

  // ---- one-shot actions (on/off/toggle/resize/...) ----
  // A single runner serialises them; a click that lands mid-flight is
  // remembered and runs next, so rapid toggles never drop the last intent.
  // After the queue drains the status is re-read.
  property Process actionProc: Process {
    id: actionProc
    stderr: StdioCollector { id: stderrCollector; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        var lines = String(stderrCollector.text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trim() !== "") root.notify(lines[i].trim())
        }
      }
      if (root._pendingArgs !== null && root._pendingArgs !== undefined) {
        var next = root._pendingArgs
        root._pendingArgs = null
        root.startAction(next)
      } else {
        root.refresh(true)
      }
    }
  }

  function startAction(args) {
    var command = [root.cliPath]
    for (var i = 0; i < args.length; i++) command.push(String(args[i]))
    actionProc.command = command
    actionProc.running = true
  }

  function runAction(args) {
    if (actionProc.running) {
      root._pendingArgs = args
      return
    }
    root.startAction(args)
  }

  // ---- picker (blocking menu via omarchy-menu-select in the CLI) ----
  property Process pickCameraProc: Process {
    id: pickCameraProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._picking = false
        var device = text.trim()
        if (device !== "") root._camera = device
      }
    }
    onExited: function() {
      root._picking = false
      root.refresh(true)
    }
  }

  // ---------------------------------------------------------- public API
  // Always refreshes the cheap status; optionally also refreshes the lazy
  // camera and setting labels (panel open, camera pick done, or setting change).
  function refresh(full) {
    if (!statusProc.running) statusProc.running = true
    if (full && !settingsProc.running) settingsProc.running = true
  }

  function on() { root.runAction(["on"]) }
  function off() { root.runAction(["off"]) }
  function toggle() {
    if (root.active) root.off()
    else root.on()
  }

  function setSize(size) {
    var value = String(size || "")
    if (["small", "medium", "large"].indexOf(value) < 0) return
    if (value === root._size) return
    root._size = value
    root.runAction(["resize", value])
  }

  function stepSize(direction) {
    var value = String(direction || "")
    if (["smaller", "larger"].indexOf(value) < 0) return
    root.runAction([value])
  }

  function setOrientation(orientation) {
    var value = String(orientation || "")
    if (["portrait", "landscape"].indexOf(value) < 0) return
    if (value === root._orientation) return
    root._orientation = value
    root.runAction(["orientation", value])
  }

  function setRounding(px) {
    var value = String(px ?? "")
    if (!/^[0-9]+$/.test(value)) return
    if (value === root._rounding) return
    root._rounding = value
    root.runAction(["rounding", value])
  }

  function setPosition(position) {
    var value = String(position || "")
    if (["top-left", "top-right", "bottom-left", "bottom-right"].indexOf(value) < 0) return
    if (value === root._position) return
    root._position = value
    root.runAction(["position", value])
  }

  function resetDefaults() {
    root.runAction(["reset"])
  }

  function pickCamera() {
    if (pickCameraProc.running || actionProc.running) return
    root._picking = true
    pickCameraProc.command = [root.cliPath, "pick-device"]
    pickCameraProc.running = true
  }

  // Keep the bar dot live while the shell runs. Only the (single, cheap) status
  // probe is repeated; camera/size labels refresh when the panel opens or an
  // action lands. Interval is generous to keep CPU near zero when idle.
  property Timer pollTimer: Timer {
    id: pollTimer
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  // External edits (terminal CLI, reset) land in the state omarec.conf — pick
  // them up so the panel never disagrees with the file. The state dir is
  // outside the plugin folder, so watching it never triggers a plugin reload.
  property FileView confWatcher: FileView {
    id: confWatcherView
    path: root.confPath
    watchChanges: true
    printErrors: false
    onFileChanged: {
      confWatcherView.reload()
      confDebounce.restart()
    }
  }

  property Timer confDebounce: Timer {
    id: confDebounce
    interval: 300
    repeat: false
    onTriggered: root.refresh(true)
  }

  Component.onCompleted: root.refresh(true)

  // --------------------------------------------------------------- IPC
  property IpcHandler ipc: IpcHandler {
    id: ipc
    target: "io.github.theneovimmer.omarec"

    function on(): string {
      root.on()
      return "ok"
    }
    function off(): string {
      root.off()
      return "ok"
    }
    function toggle(): string {
      root.toggle()
      return root._state
    }
    function open(): string {
      if (root.shell && typeof root.shell.summon === "function") root.shell.summon("io.github.theneovimmer.omarec")
      return "ok"
    }
    function close(): string {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide("io.github.theneovimmer.omarec")
      return "ok"
    }
    function refresh(): string {
      root.refresh(true)
      return "ok"
    }
    function status(): string {
      return root._state
    }
    function size(): string {
      return root._size
    }
    function setSize(value: string): string {
      root.setSize(value)
      return "ok"
    }
    function device(): string {
      return root._camera
    }
    function pickDevice(): string {
      root.pickCamera()
      return "ok"
    }
    function orientation(): string {
      return root._orientation
    }
    function setOrientation(value: string): string {
      root.setOrientation(value)
      return "ok"
    }
    function rounding(): string {
      return root._rounding
    }
    function setRounding(value: string): string {
      root.setRounding(value)
      return "ok"
    }
    function position(): string {
      return root._position
    }
    function setPosition(value: string): string {
      root.setPosition(value)
      return "ok"
    }
    function reset(): string {
      root.resetDefaults()
      return "ok"
    }
  }
}
