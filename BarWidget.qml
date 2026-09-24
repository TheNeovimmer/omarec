pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Bar entry point for OMARec: a camera icon that becomes a LIVE pill while the
// floating camera overlay is up, plus a compact Studio control panel. The UI is
// deliberately minimal: no PanelHero, no toggle switch — instead a
// minimal header row with a start/stop button, native segmented controls for
// size, framing and rounding, a corner pad for position, and a live geometry
// preview showing exactly where the bubble will land.
Panel {
  id: root

  ipcTarget: ""
  manageIpc: false

  readonly property var service: bar && bar.shell && moduleName ? bar.shell.serviceFor(moduleName) : null

  // ---- service state (always defined so the UI never reads null) -------
  readonly property bool live: service ? service.active : false
  readonly property string camera: service ? service.camera : ""
  readonly property string size: service ? service.size : "medium"
  readonly property string orientation: service ? service.orientation : "portrait"
  readonly property string rounding: service ? service.rounding : "12"
  readonly property string position: service ? service.position : "bottom-right"
  readonly property bool busy: service ? service.busy : false
  readonly property bool picking: service ? service.picking : false
  readonly property bool degraded: service ? service.degraded : false
  readonly property string degradedHint: service ? service.degradedHint : ""

  readonly property bool showWhenIdle: setting("showWhenIdle", true) !== false
  readonly property bool pillMode: root.live
  // A live widget must stay visible or it could never be stopped.
  readonly property bool shown: root.pillMode || root.showWhenIdle
  readonly property bool visibleInBar: root.shown || root.opened
  visible: root.visibleInBar
  implicitWidth: root.visibleInBar ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  // ---- theme -----------------------------------------------------------
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color barDim: Qt.darker(barForeground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: Style.hoverFillFor(foreground, accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, accent)

  // ---- bar pill --------------------------------------------------------
  readonly property string pillText: "LIVE"
  readonly property color pillFill: root.degraded ? root.barDim : root.accent
  readonly property color pillForeground: Color.background
  readonly property real pillWidth: Math.round(pillMetrics.width) + Style.space(30)

  // ---- bar icon: camera glyph when idle, LIVE pill when live ---------
  readonly property bool serviceMissing: !root.service

  readonly property string tooltip: {
    if (!root.service) return "OMARec — service not loaded"
    if (root.busy && !root.live) return "OMARec — working…"
    if (root.live) return "OMARec — live on " + (root.camera || "default")
    if (root.degraded) return "OMARec — degraded: " + (root.degradedHint || "CLI unavailable")
    return "OMARec — off"
  }

  // ---- panel -----------------------------------------------------------
  readonly property string aspectLabel: root.orientation === "landscape" ? "16:9" : "8:9"
  readonly property string positionLabel: {
    if (root.position === "top-left") return "Top left"
    if (root.position === "top-right") return "Top right"
    if (root.position === "bottom-left") return "Bottom left"
    return "Bottom right"
  }
  // Overlay footprint as fractions of a 16:9 screen, mirroring the monitor_h
  // geometry in bin/omarec so the preview shows true proportions.
  readonly property var previewGeom: {
    var landscape = root.orientation === "landscape"
    var w, h
    if (landscape) {
      w = root.size === "small" ? 0.25 : (root.size === "large" ? 0.45 : 0.375)
      h = w
    } else {
      w = root.size === "small" ? 0.09 : (root.size === "large" ? 0.16875 : 0.125)
      h = root.size === "small" ? 0.18 : (root.size === "large" ? 0.3375 : 0.25)
    }
    return { "w": w, "h": h }
  }
  readonly property bool previewLeft: root.position === "top-left" || root.position === "bottom-left"
  readonly property bool previewTop: root.position === "top-left" || root.position === "top-right"

  readonly property string heroMeta: {
    if (!root.service) return "Service not loaded"
    if (root.live) return "Live · " + (root.camera || "default camera")
    return "Ready · " + root.orientation + " " + root.aspectLabel + " · " + root.size
  }

  // ---- cursor ----------------------------------------------------------
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property var nav: [
    "toggle", "camera-pick",
    "size-small", "size-medium", "size-large",
    "orient-portrait", "orient-landscape",
    "rounding-0", "rounding-8", "rounding-12",
    "rounding-16", "rounding-20",
    "position-top-left", "position-top-right",
    "position-bottom-left", "position-bottom-right",
    "reset"
  ]

  function navIndex(kind) { return root.nav.indexOf(kind) }
  function hasCursorAt(kind) { return root.cursorActive && root.navIndex(kind) === root.cursorIndex }
  function moveCursor(dy) {
    root.cursorActive = true
    var n = root.nav.length
    root.cursorIndex = Math.max(0, Math.min(n - 1, root.cursorIndex + dy))
  }
  function setCursor(kind) {
    var i = root.navIndex(kind)
    if (i < 0) return
    root.cursorActive = true
    root.cursorIndex = i
  }
  // Map the flat panel cursor onto one ButtonGroup's chip index, or -1 when
  // the cursor sits outside that group. Keeps arrow-key navigation working
  // across groups while each group keeps its native single-row behaviour.
  function groupCursor(first, count) {
    if (!root.cursorActive) return -1
    var base = root.navIndex(first)
    if (base < 0) return -1
    var offset = root.cursorIndex - base
    return (offset >= 0 && offset < count) ? offset : -1
  }
  function groupHover(first, count, index, isHovered) {
    if (!isHovered) return
    var base = root.navIndex(first)
    if (base < 0 || index < 0 || index >= count) return
    root.cursorActive = true
    root.cursorIndex = base + index
  }
  function activateCursor() {
    var kind = root.nav[root.cursorIndex]
    if (kind === "toggle") root.toggle()
    else if (kind === "camera-pick") root.pickCamera()
    else if (kind === "reset") root.resetDefaults()
    else if (kind.indexOf("size-") === 0) root.applySize(kind.slice(5))
    else if (kind.indexOf("orient-") === 0) root.applyOrientation(kind.slice(7))
    else if (kind.indexOf("rounding-") === 0) root.applyRounding(kind.slice(9))
    else if (kind.indexOf("position-") === 0) root.applyPosition(kind.slice(9))
  }

  function toggle() { if (root.service && !root.busy) root.service.toggle() }
  function applySize(value) { if (root.service) root.service.setSize(value) }
  function applyOrientation(value) { if (root.service) root.service.setOrientation(value) }
  function applyRounding(value) { if (root.service && /^[0-9]+$/.test(value)) root.service.setRounding(value) }
  function applyPosition(value) { if (root.service) root.service.setPosition(value) }
  function pickCamera() { if (root.service && !root.busy) root.service.pickCamera() }
  function resetDefaults() { if (root.service && !root.busy) root.service.resetDefaults() }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    if (root.service) root.service.refresh(true)
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  TextMetrics {
    id: pillMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
    text: root.pillText
  }

  // ---- bar icon --------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltip
    slotSize: root.pillMode ? root.pillWidth : Style.bar.iconSlot
    opticalSize: root.pillMode ? root.pillWidth : Style.bar.iconCanvas

    iconComponent: Component {
      Item {
        anchors.fill: parent

        // LIVE pill while the overlay is up.
        BorderSurface {
          anchors.centerIn: parent
          visible: root.pillMode
          implicitWidth: root.pillWidth
          implicitHeight: Math.round(pillMetrics.height) + Style.space(6)
          radius: Style.cornerRadius > 0 ? implicitHeight / 2 : 0
          color: root.pillFill
          borderSpec: Border.none()

          Row {
            anchors.centerIn: parent
            spacing: Style.space(5)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: width
              radius: width / 2
              color: root.pillForeground
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.pillText
              color: root.pillForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        // Camera glyph when idle — green when live is unreachable here
        // because live shows the pill instead; dimmed when degraded.
        Text {
          visible: !root.pillMode
          anchors.centerIn: parent
          text: "󰅱"
          color: root.serviceMissing ? root.barDim : root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          opacity: root.serviceMissing ? 0.4 : 0.85
        }
      }
    }

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.service && !root.busy) root.service.toggle()
        return
      }
      if (root.opened) root.close()
      else root.open()
    }
  }

  // ---- panel -----------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(540))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          // ---- header (no PanelHero, no toggle switch) ----
          Item {
            width: parent.width
            implicitHeight: headerRow.implicitHeight + Style.space(8)

            RowLayout {
              id: headerRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: Style.space(4)
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Column {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                  text: "OMARec"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  text: root.busy ? "Working…" : root.heroMeta
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              Button {
                text: root.busy ? "…" : (root.live ? "Stop" : "Start")
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                enabled: !root.picking && !root.busy
                opacity: enabled ? 1.0 : 0.4
                hasCursor: root.hasCursorAt("toggle")
                onHovered: function (on) { if (on) root.setCursor("toggle") }
                onClicked: root.toggle()
              }
            }
          }

          // Warning line.
          Text {
            visible: text !== ""
            width: parent.width - Style.space(20)
            x: Style.space(10)
            text: {
              if (!root.service) return "The OMARec service is not loaded."
              if (root.degraded) return root.degradedHint !== "" ? root.degradedHint : "The OMARec CLI is unavailable."
              if (root.picking) return "Choose a camera…"
              return ""
            }
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.foreground }

          // ---- device ----
          PanelSectionHeader {
            text: "DEVICE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          CursorSurface {
            width: column.width
            hasCursor: root.hasCursorAt("camera-pick")
            foreground: root.foreground
            fill: root.hoverFill
            currentFill: root.selectedFill
            implicitHeight: camInner.implicitHeight + Style.spacing.rowPaddingX

            RowLayout {
              id: camInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(8)

              Text {
                text: "󰋎"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                Layout.alignment: Qt.AlignVCenter
              }

              Text {
                Layout.fillWidth: true
                text: root.camera === "" ? "None selected" : root.camera
                elide: Text.ElideMiddle
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              PanelActionButton {
                Layout.alignment: Qt.AlignVCenter
                iconText: "󰅙"
                tooltipText: "Choose a webcam"
                foreground: root.foreground
                hoverColor: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.picking && !root.busy
                opacity: enabled ? 1.0 : 0.4
                onHovered: function (on) { if (on) root.setCursor("camera-pick") }
                onClicked: root.pickCamera()
              }
            }
          }

          // ---- size ----
          PanelSectionHeader {
            text: "SIZE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          BorderSurface {
            width: column.width - Style.space(20)
            x: Style.space(10)
            implicitHeight: sizeGroup.implicitHeight + Style.spacing.rowPaddingX * 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

            ButtonGroup {
              id: sizeGroup
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(14)
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: false
              options: [
                { value: "small", label: "Small", tooltip: "Compact bubble" },
                { value: "medium", label: "Medium", tooltip: "Balanced bubble" },
                { value: "large", label: "Large", tooltip: "Large bubble" }
              ]
              value: root.size
              cursorIndex: root.groupCursor("size-small", 3)
              onChanged: function (v) { root.applySize(v) }
              onHovered: function (index, isHovered) { root.groupHover("size-small", 3, index, isHovered) }
            }
          }

          // ---- framing ----
          PanelSectionHeader {
            text: "FRAMING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          BorderSurface {
            width: column.width - Style.space(20)
            x: Style.space(10)
            implicitHeight: framingGroup.implicitHeight + Style.spacing.rowPaddingX * 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

            ButtonGroup {
              id: framingGroup
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(14)
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: false
              options: [
                { value: "portrait", label: "Portrait", tooltip: "Tall 8:9 crop" },
                { value: "landscape", label: "Landscape", tooltip: "Wide 16:9 crop" }
              ]
              value: root.orientation
              cursorIndex: root.groupCursor("orient-portrait", 2)
              onChanged: function (v) { root.applyOrientation(v) }
              onHovered: function (index, isHovered) { root.groupHover("orient-portrait", 2, index, isHovered) }
            }
          }

          // Rounding
          PanelSectionHeader {
            text: "ROUNDING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          BorderSurface {
            width: column.width - Style.space(20)
            x: Style.space(10)
            implicitHeight: roundingGroup.implicitHeight + Style.spacing.rowPaddingX * 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

            ButtonGroup {
              id: roundingGroup
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(14)
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: false
              options: [
                { value: "0", label: "Off", tooltip: "Square corners" },
                { value: "8", label: "8px" },
                { value: "12", label: "12px" },
                { value: "16", label: "16px" },
                { value: "20", label: "20px", tooltip: "Maximum rounding" }
              ]
              value: root.rounding
              cursorIndex: root.groupCursor("rounding-0", 5)
              onChanged: function (v) { root.applyRounding(v) }
              onHovered: function (index, isHovered) { root.groupHover("rounding-0", 5, index, isHovered) }
            }
          }

          Text {
            width: column.width - Style.space(20)
            x: Style.space(10)
            text: "Hyprland supports up to 20px."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // ---- position ----
          PanelSectionHeader {
            text: "POSITION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Grid {
            width: column.width - Style.space(20)
            x: Style.space(10)
            columns: 2
            spacing: Style.space(6)

            Repeater {
              model: [
                { value: "top-left", label: "Top left" },
                { value: "top-right", label: "Top right" },
                { value: "bottom-left", label: "Bottom left" },
                { value: "bottom-right", label: "Bottom right" }
              ]

              Button {
                required property var modelData
                width: (parent.width - parent.columnSpacing) / 2
                text: modelData.label
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                selected: root.position === modelData.value
                hasCursor: root.hasCursorAt("position-" + modelData.value)
                onHovered: function (on) { if (on) root.setCursor("position-" + modelData.value) }
                onClicked: root.applyPosition(modelData.value)
              }
            }
          }

          // ---- preview ----
          PanelSectionHeader {
            text: "PREVIEW"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // A 16:9 screen mock with the bubble drawn at its true relative
          // size, shape and corner — the fractions mirror bin/omarec's
          // monitor_h geometry, so what you see is where mpv will land.
          BorderSurface {
            width: column.width - Style.space(20)
            x: Style.space(10)
            implicitHeight: Math.round(width * 9 / 16)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

            Rectangle {
              width: Math.max(Style.space(16), parent.width * root.previewGeom.w)
              height: Math.max(Style.space(16), parent.height * root.previewGeom.h)
              x: root.previewLeft ? Style.space(6) : parent.width - width - Style.space(6)
              y: root.previewTop ? Style.space(6) : parent.height - height - Style.space(6)
              color: root.accent
              opacity: root.live ? 1.0 : 0.55
              radius: Math.min(width, height) * Number(root.rounding) / 40
            }
          }

          Text {
            width: column.width - Style.space(20)
            x: Style.space(10)
            text: root.positionLabel + " · " + root.aspectLabel + " · " + root.size
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { foreground: root.foreground }

          CursorSurface {
            width: column.width
            hasCursor: root.hasCursorAt("reset")
            foreground: root.foreground
            fill: root.hoverFill
            currentFill: root.selectedFill
            implicitHeight: resetInner.implicitHeight + Style.spacing.rowPaddingX

            RowLayout {
              id: resetInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: "Reset to defaults"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              PanelActionButton {
                Layout.alignment: Qt.AlignVCenter
                iconText: "󰅙"
                tooltipText: "Restore default size, framing, rounding and position"
                foreground: root.foreground
                hoverColor: root.foreground
                fontFamily: root.fontFamily
                enabled: !root.busy
                opacity: enabled ? 1.0 : 0.4
                onHovered: function (on) { if (on) root.setCursor("reset") }
                onClicked: root.resetDefaults()
              }
            }
          }

          Text {
            width: column.width - Style.space(20)
            x: Style.space(10)
            text: "Right-click the bar icon for a quick toggle. OMARec is a live camera overlay only — it never records."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
