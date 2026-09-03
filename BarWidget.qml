pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Bar entry point for OMARec: a camera pill that lights up when the floating
// live camera overlay is up, plus the control panel behind it. The UI follows
// the same design language as Omarchy's first-party plugins (on-air): a
// BorderSurface chip in the bar, a PanelHero with a toggle, action buttons
// under the hero, and sectioned rows. Instanced once per monitor, so it owns
// no Process, Timer or IpcHandler — every action goes through the single
// Service instance (bar.shell.serviceFor(moduleName)), null-guarded at every
// access (it is transiently null during load and after each hot reload).
Panel {
  id: root

  // The service registers the "omarec" IPC target; the Panel base must not
  // register a second one per monitor.
  ipcTarget: ""
  manageIpc: false

  readonly property var service: bar && bar.shell && moduleName ? bar.shell.serviceFor(moduleName) : null

  // ---- service state, always defined so the UI never reads a null -------
  readonly property bool onAir: service ? service.active : false
  readonly property string camera: service ? service.camera : ""
  readonly property string size: service ? service.size : "medium"
  readonly property string orientation: service ? service.orientation : "portrait"
  readonly property string rounding: service ? service.rounding : "12"
  readonly property bool busy: service ? service.busy : false
  readonly property bool picking: service ? service.picking : false

  // Always visible: the bar entry is the only way to reach the overlay.
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

  // ---- bar visuals (on-air style pill) --------------------------------
  // Live dot + camera glyph + a "LIVE" pill in that order; idle is the glyph.
  readonly property bool pillMode: root.onAir
  readonly property string pillText: "LIVE"
  readonly property color pillFill: root.degraded ? root.barDim : root.urgent
  readonly property color pillForeground: Color.background
  readonly property real pillWidth: Math.round(pillMetrics.width) + Style.space(34)

  // Degraded = the CLI cannot detect anything (service present but unusable).
  readonly property bool degraded: !root.service

  readonly property string tooltip: {
    if (!root.service) return "OMARec — service not loaded"
    if (root.onAir) return "OMARec — camera overlay live on " + (root.camera || "default")
    return "OMARec — camera overlay off"
  }

  // ---- hero ------------------------------------------------------------
  readonly property string heroMeta: {
    if (!root.service) return "Service not loaded"
    if (root.onAir) return "Live · " + (root.camera || "default camera")
    return "Off air"
  }
  readonly property string statusDetail: busy
    ? "Working…"
    : (onAir ? "On" : "Off")

  readonly property string toggleHint: root.onAir ? "Turn camera overlay off" : "Turn camera overlay on"

  // ---- panel cursor ----------------------------------------------------
  property bool cursorActive: false
  property int cursorIndex: 0

  readonly property var nav: ["hero", "toggle", "camera-pick", "size-small", "size-medium", "size-large",
    "orient-portrait", "orient-landscape", "rounding-0", "rounding-8", "rounding-16", "rounding-24"]

  function navIndex(kind) { return root.nav.indexOf(kind) }
  function hasCursorAt(kind) { return root.cursorActive && root.navIndex(kind) === root.cursorIndex }
  function moveCursor(dy) {
    root.cursorActive = true
    var n = root.nav.length
    var next = Math.max(0, Math.min(n - 1, root.cursorIndex + dy))
    root.cursorIndex = next
  }
  function setCursor(kind) {
    var i = root.navIndex(kind)
    if (i < 0) return
    root.cursorActive = true
    root.cursorIndex = i
  }
  function activateCursor() {
    var kind = root.nav[root.cursorIndex]
    if (kind === "hero" || kind === "toggle") root.toggle()
    else if (kind === "camera-pick") root.pickCamera()
    else if (kind === "size-small") root.applySize("small")
    else if (kind === "size-medium") root.applySize("medium")
    else if (kind === "size-large") root.applySize("large")
    else if (kind === "orient-portrait") root.applyOrientation("portrait")
    else if (kind === "orient-landscape") root.applyOrientation("landscape")
    else if (kind.indexOf("rounding-") === 0) root.applyRounding(kind.slice("rounding-".length))
  }

  function toggle() { if (root.service) root.service.toggle() }
  function applySize(value) { if (root.service) root.service.setSize(value) }
  function applyOrientation(value) { if (root.service) root.service.setOrientation(value) }
  function applyRounding(value) { if (root.service && /^[0-9]+$/.test(value)) root.service.setRounding(value) }
  function pickCamera() { if (root.service) root.service.pickCamera() }

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

        // LIVE pill (only while the overlay is up), mirroring on-air's pill.
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
            spacing: Style.space(6)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: width
              radius: width / 2
              color: root.pillForeground
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰻂"
              color: root.pillForeground
              font.family: root.fontFamily
              font.pixelSize: Style.bar.iconFont
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

        // Idle: a neutral camera glyph (dimmed if degraded/unavailable).
        Text {
          anchors.centerIn: parent
          visible: !root.pillMode
          text: "󰻂"
          color: root.degraded ? root.barDim : root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
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

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

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
          spacing: Style.space(12)

          // ------------------------------------------------------- hero
          Item {
            id: heroWrap
            width: parent.width
            implicitHeight: hero.implicitHeight

            readonly property bool ringVisible: root.hasCursorAt("hero")
            readonly property bool switchChecked: root.onAir
            readonly property string hint: root.toggleHint
            function focusHero() { root.setCursor("hero") }
            function activate() { root.toggle() }

            PanelHero {
              id: hero
              width: parent.width
              title: "OMARec"
              meta: root.heroMeta
              detail: root.statusDetail
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.onAir ? 1.0 : 0.5

              iconComponent: Component {
                Rectangle {
                  implicitWidth: Style.font.display
                  implicitHeight: Style.font.display
                  radius: width / 2
                  color: root.onAir ? root.urgent : "transparent"
                  border.width: Math.max(1, Style.space(2))
                  border.color: root.onAir ? root.urgent : root.dim
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: airSwitch
                  checked: heroWrap.switchChecked
                  hasCursor: heroWrap.ringVisible
                  foreground: hero.foreground
                  onHovered: function (on) { if (on) heroWrap.focusHero() }
                  onToggled: heroWrap.activate()

                  PanelToolTip {
                    visible: airSwitch.containsMouse
                    text: heroWrap.hint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          // Status / warning line, exactly like on-air's degraded message.
          Text {
            visible: text !== ""
            width: parent.width
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

          // ----------------------------------------------------- actions
          PanelSeparator { foreground: root.foreground }

          Row {
            width: column.width
            spacing: Style.space(8)
            leftPadding: Style.space(10)

            Button {
              text: root.onAir ? "Camera off" : "Camera on"
              iconText: root.onAir ? "󰅺" : "󰅱"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.picking
              opacity: enabled ? 1.0 : 0.4
              hasCursor: root.hasCursorAt("hero")
              onHovered: function (on) { if (on) root.setCursor("hero") }
              onClicked: root.toggle()
            }

            Button {
              text: "Pick camera"
              iconText: "󰅙"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.picking
              opacity: enabled ? 1.0 : 0.4
              hasCursor: root.hasCursorAt("camera-pick")
              onHovered: function (on) { if (on) root.setCursor("camera-pick") }
              onClicked: root.pickCamera()
            }
          }

          // ------------------------------------------------------ camera
          PanelSectionHeader {
            text: "CAMERA"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          CursorSurface {
            id: cameraRow
            width: column.width
            hasCursor: root.hasCursorAt("camera-pick")
            foreground: root.foreground
            fill: root.hoverFill
            currentFill: root.selectedFill
            implicitHeight: cameraInner.implicitHeight + Style.spacing.rowPaddingX

            RowLayout {
              id: cameraInner
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
                text: root.camera === "" ? "None" : root.camera
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

          // --------------------------------------------------------- size
          PanelSectionHeader {
            text: "SIZE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: column.width
            spacing: Style.space(8)
            leftPadding: Style.space(10)

            Repeater {
              model: ["small", "medium", "large"]

              Button {
                required property string modelData
                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                selected: root.size === modelData
                hasCursor: root.hasCursorAt("size-" + modelData)
                onHovered: function (on) { if (on) root.setCursor("size-" + modelData) }
                onClicked: root.applySize(modelData)
              }
            }
          }

          // --------------------------------------------------- orientation
          PanelSectionHeader {
            text: "ORIENTATION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: column.width
            spacing: Style.space(8)
            leftPadding: Style.space(10)

            Button {
              text: "Portrait"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              selected: root.orientation === "portrait"
              hasCursor: root.hasCursorAt("orient-portrait")
              onHovered: function (on) { if (on) root.setCursor("orient-portrait") }
              onClicked: root.applyOrientation("portrait")
            }

            Button {
              text: "Landscape"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              selected: root.orientation === "landscape"
              hasCursor: root.hasCursorAt("orient-landscape")
              onHovered: function (on) { if (on) root.setCursor("orient-landscape") }
              onClicked: root.applyOrientation("landscape")
            }
          }

          // ------------------------------------------------------- rounding
          PanelSectionHeader {
            text: "ROUNDING"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: column.width
            spacing: Style.space(8)
            leftPadding: Style.space(10)

            Repeater {
              model: ["0", "8", "16", "24"]

              Button {
                required property string modelData
                text: modelData === "0" ? "Square" : modelData + "px"
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

          // --------------------------------------------------- shortcuts
          PanelSeparator { foreground: root.foreground }

          Text {
            width: column.width - Style.space(20)
            x: Style.space(10)
            text: "Right-click the bar pill to toggle quickly. The overlay mirrors screen-recording's — live webcam only, never records."
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