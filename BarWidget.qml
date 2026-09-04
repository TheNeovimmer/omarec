pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Bar entry point for OMARec: a camera icon that pulses when the live camera
// overlay is active, plus a compact Studio control panel. The UI is deliberately
// distinct from on-air: no PanelHero, no toggle switch — instead a minimal
// header row with a start/stop button and grouped appearance/position grids.
Panel {
  id: root

  ipcTarget: ""
  manageIpc: false

  readonly property var service: bar && bar.shell && moduleName ? bar.shell.serviceFor(moduleName) : null

  // ---- service state (always defined so the UI never reads null) -------
  readonly property bool onAir: service ? service.active : false
  readonly property string camera: service ? service.camera : ""
  readonly property string size: service ? service.size : "medium"
  readonly property string orientation: service ? service.orientation : "portrait"
  readonly property string rounding: service ? service.rounding : "12"
  readonly property string position: service ? service.position : "bottom-right"
  readonly property bool busy: service ? service.busy : false
  readonly property bool picking: service ? service.picking : false

  readonly property bool shown: true
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

  // ---- bar icon (distinct from on-air: glyph + live dot) ---------------
  readonly property bool degraded: !root.service

  readonly property string tooltip: {
    if (!root.service) return "OMARec — service not loaded"
    if (root.onAir) return "OMARec — live on " + (root.camera || "default")
    return "OMARec — off"
  }

  // ---- panel -----------------------------------------------------------
  readonly property string heroMeta: {
    if (!root.service) return "Service not loaded"
    if (root.onAir) return "Live · " + (root.camera || "default camera")
    return "Ready · " + root.orientation + " · " + root.size
  }

  // ---- cursor ----------------------------------------------------------
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property var nav: [
    "toggle", "camera-pick",
    "size-small", "size-medium", "size-large",
    "orient-portrait", "orient-landscape",
    "rounding-0", "rounding-8", "rounding-16",
    "rounding-20",
    "position-top-left", "position-top-right",
    "position-bottom-left", "position-bottom-right"
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
  function activateCursor() {
    var kind = root.nav[root.cursorIndex]
    if (kind === "toggle") root.toggle()
    else if (kind === "camera-pick") root.pickCamera()
    else if (kind.indexOf("size-") === 0) root.applySize(kind.slice(5))
    else if (kind.indexOf("orient-") === 0) root.applyOrientation(kind.slice(7))
    else if (kind.indexOf("rounding-") === 0) root.applyRounding(kind.slice(9))
    else if (kind.indexOf("position-") === 0) root.applyPosition(kind.slice(9))
  }

  function toggle() { if (root.service) root.service.toggle() }
  function applySize(value) { if (root.service) root.service.setSize(value) }
  function applyOrientation(value) { if (root.service) root.service.setOrientation(value) }
  function applyRounding(value) { if (root.service && /^[0-9]+$/.test(value)) root.service.setRounding(value) }
  function applyPosition(value) { if (root.service) root.service.setPosition(value) }
  function pickCamera() { if (root.service) root.service.pickCamera() }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    if (root.service) root.service.refresh(true)
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  // ---- bar icon --------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltip
    slotSize: Style.bar.iconSlot
    opticalSize: Style.bar.iconCanvas

    iconComponent: Component {
      Item {
        anchors.fill: parent

        // Camera glyph — green when live, dimmed when off or degraded.
        Text {
          anchors.centerIn: parent
          text: "󰅱"
          color: root.onAir
            ? root.accent
            : (root.degraded ? root.barDim : root.barForeground)
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          opacity: root.onAir ? 1.0 : (root.degraded ? 0.4 : 0.85)
        }

        // Live indicator dot (bottom-right of the glyph).
        Rectangle {
          visible: root.onAir
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: Style.space(2)
          anchors.bottomMargin: Style.space(2)
          width: Style.space(6)
          height: width
          radius: width / 2
          color: root.accent
        }
      }
    }

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.service) root.service.toggle()
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
                  text: root.heroMeta
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              Button {
                text: root.onAir ? "Stop" : "Start"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                enabled: !root.picking
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
                enabled: !root.picking
                opacity: enabled ? 1.0 : 0.4
                onHovered: function (on) { if (on) root.setCursor("camera-pick") }
                onClicked: root.pickCamera()
              }
            }
          }

          // ---- appearance ----
          PanelSectionHeader {
            text: "APPEARANCE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // Size + Orientation in a compact 2-column grid.
          Grid {
            width: column.width - Style.space(20)
            x: Style.space(10)
            columns: 2
            spacing: Style.space(6)

            Repeater {
              model: [
                { label: "Small", size: "small" },
                { label: "Medium", size: "medium" },
                { label: "Large", size: "large" },
                { label: "Portrait", orient: "portrait" },
                { label: "Landscape", orient: "landscape" }
              ]

              Button {
                required property var modelData
                width: (parent.width - parent.columnSpacing) / 2
                text: modelData.label
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                selected: modelData.size
                  ? root.size === modelData.size
                  : root.orientation === modelData.orient
                hasCursor: modelData.size
                  ? root.hasCursorAt("size-" + modelData.size)
                  : root.hasCursorAt("orient-" + modelData.orient)
                onHovered: function (on) {
                  if (on) root.setCursor(modelData.size ? "size-" + modelData.size : "orient-" + modelData.orient)
                }
                onClicked: modelData.size ? root.applySize(modelData.size) : root.applyOrientation(modelData.orient)
              }
            }
          }

          // Rounding
          PanelSectionHeader {
            text: "ROUNDING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: column.width
            spacing: Style.space(6)
            leftPadding: Style.space(10)

            Repeater {
              model: ["0", "8", "16", "20"]

              Button {
                required property string modelData
                text: modelData === "0" ? "Off" : modelData + "px"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                selected: root.rounding === modelData
                hasCursor: root.hasCursorAt("rounding-" + modelData)
                onHovered: function (on) { if (on) root.setCursor("rounding-" + modelData) }
                onClicked: root.applyRounding(modelData)
              }
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

          PanelSeparator { foreground: root.foreground }

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
