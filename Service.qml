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
// the bar menu and keybinds use, so nothing can drift. The CLI reuses Omarchy's
// shipped `WebcamOverlay` window rules, so this plugin never touches
// hyprland.lua or any Omarchy config.
QtObject {
  id: root

  // ------------------------------------------------------------- injected
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""

  // ------------------------------------------------------- public surface
  // The floating overlay is up when hyprctl sees a WebcamOverlay window.
  readonly property string state: _state
  readonly property bool active: _state === "running"
  // Remembered device and size, resolved off the CLI so the panel and tooltip
  // agree with what bin/omarec will actually use.
  readonly property string camera: _camera
  readonly property string size: _size
  readonly property string orientation: _orientation
  readonly property string rounding: _rounding
  readonly property string position: _position
  // True while a picker menu is up; the panel can dim its Change button.
  readonly property bool picking: _picking
  readonly property bool busy: statusProc.running || actionProc.running

  // Resolved once: the plugin dir is wherever the shell loaded this file from.
  readonly property string pluginDir: {
    var value = String(Qt.resolvedUrl(".") || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    if (value.charAt(value.length - 1) !== "/") value += "/"
    return decodeURIComponent(value)
  }
  readonly property string cliPath: pluginDir + "bin/omarec"

  // -------------------------------------------------------------- private
  property string _state: "stopped"
  property string _camera: ""
  property string _size: "medium"
  property string _orientation: "portrait"
  property string _rounding: "12"
  property string _position: "bottom-right"
  property bool _picking: false

  // When the overlay state changed since we last read it, nudge every widget
  // so the glyph/dot and panel stay in sync even while the panel is open.
  signal overlayChanged(bool active)

  // ------------------------------------------------------------ utilities
  function notify(message) {
    var base = root.omarchyPath || Quickshell.env("OMARCHY_PATH") || ""
    var binary = base !== "" ? base + "/bin/omarchy-notification-send" : "omarchy-notification-send"
    Quickshell.execDetached([binary, "OMARec", String(message)])
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

  // ---- remembered settings (refreshed lazily) ----
  // The device and preset only change through explicit user action (pick / set),
  // so unlike status they are NOT polled every tick — that keeps the steady-state
  // cost of this service to a single cheap `status` process per poll.
  property Process cameraProc: Process {
    id: cameraProc
    command: [root.cliPath, "get-device"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._camera = text.trim() }
  }
  property Process sizeProc: Process {
    id: sizeProc
    command: [root.cliPath, "get-size"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._size = text.trim() || "medium" }
  }
  property Process orientationProc: Process {
    id: orientationProc
    command: [root.cliPath, "get-orientation"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._orientation = text.trim() || "portrait" }
  }
  property Process roundingProc: Process {
    id: roundingProc
    command: [root.cliPath, "get-rounding"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._rounding = text.trim() || "12" }
  }
  property Process positionProc: Process {
    id: positionProc
    command: [root.cliPath, "get-position"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._position = text.trim() || "bottom-right" }
  }

  // ---- one-shot actions (on/off/toggle/resize) ----
  // A single runner serialises them; after each action the status is re-read.
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
      root.refresh(true)
    }
  }

  function runAction(args) {
    if (actionProc.running) return
    var command = [root.cliPath]
    for (var i = 0; i < args.length; i++) command.push(String(args[i]))
    actionProc.command = command
    actionProc.running = true
  }

  // ---- picker (blocking menu via omarchy-menu-select in the CLI) ----
  property Process pickCameraProc: Process {
    id: pickCameraProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._picking = false
        root._camera = text.trim()
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
    if (full) {
      if (!cameraProc.running) cameraProc.running = true
      if (!sizeProc.running) sizeProc.running = true
      if (!orientationProc.running) orientationProc.running = true
      if (!roundingProc.running) roundingProc.running = true
      if (!positionProc.running) positionProc.running = true
    }
  }

  function on() { root.runAction(["on"]) }
  function off() { root.runAction(["off"]) }
  function toggle() {
    if (root.active) root.off()
    else root.on()
  }

  function setSize(size) {
    var value = String(size || "")
    if (value === root._size) return
    root._size = value
    root.runAction(["resize", value])
  }

  function setOrientation(orientation) {
    var value = String(orientation || "")
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

  function pickCamera() {
    if (pickCameraProc.running) return
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

  // --------------------------------------------------------------- IPC
  property IpcHandler ipc: IpcHandler {
    id: ipc
    target: "omarec"

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
      if (root.shell && typeof root.shell.summon === "function") root.shell.summon("omarec")
      return "ok"
    }
    function close(): string {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide("omarec")
      return "ok"
    }
    function refresh(): string {
      root.refresh(true)
      return "ok"
    }
    function status(): string {
      return root._state
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
  }
}
