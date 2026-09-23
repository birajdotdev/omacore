import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.birajdotdev.omacore"
  ipcTarget: "omacore"
  manageIpc: false

  property int cursorIndex: 0
  property bool cursorActive: false
  property bool effectsView: false
  readonly property bool hasSoundEffects: pods.eqOptions.length > 0 || (pods.spatialAudioSupported && pods.spatialAudioModeSupported)
  readonly property string effectsSummary: {
    if (pods.spatialAudio) return "Spatial Audio · " + Model.soundEffectLabel(pods.spatialAudioMode)
    for (var i = 0; i < pods.eqOptions.length; i++) {
      if (pods.eqOptions[i].value === pods.eqPreset) return "Default · " + pods.eqOptions[i].label
    }
    return pods.eqOptions.length ? "Custom EQ" : "Default"
  }

  function showEffects(show) {
    ncModeDropdown.close()
    eqPresetDropdown.close()
    effectsView = show
    cursorActive = false
    cursorIndex = 0
    panelFlick.contentY = 0
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function selectDefault() {
    if (!pods.eqOptions.length) { pods.setSoundEffect(Model.SOUND_EFFECT_OFF); return }
    var preset = pods.eqOptions.some(function (o) { return o.value === pods.eqPreset })
      ? pods.eqPreset : pods.eqOptions[0].value
    pods.setEqPreset(preset)
  }

  function selectSpatial() {
    pods.setSoundEffect(pods.spatialAudioMode || Model.SOUND_EFFECT_MUSIC)
  }

  readonly property bool hideWhenDisconnected: setting("hideWhenDisconnected", true) === true
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  // A missing CLI or an unregistered-but-connected device are both worth
  // showing as an alert in the bar even when the buds are (as a result)
  // unreachable — a broken setup should be loud, not invisible.
  readonly property color barIconColor: (pods.cliMissing || pods.registeredMissing) ? urgent
    : (pods.hasEarbuds ? barForeground : Qt.darker(barForeground, 1.55))
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool guidanceVisible: (!pods.hasEarbuds || pods.statusStale) && pods.lastError !== "" && !pods.cliMissing && !pods.registeredMissing
  readonly property bool ncSectionVisible: pods.ancMode === Model.MODE_NOISE_CANCELING
  readonly property bool transparencySectionVisible: pods.ancMode === Model.MODE_TRANSPARENCY && pods.transparencyModeSupported
  readonly property var ncModeOptions: Model.NC_SUBMODES.map(function (m) { return { value: m, label: Model.ncSubModeLabel(m) } })

  readonly property var cursorRows: {
    var rows = []
    if (pods.cliMissing) {
      if (pods.cliInstalling) return rows
      rows.push("installcli")
      return rows
    }
    if (pods.registeredMissing) {
      if (pods.registering) return rows
      rows.push("registerdev")
      return rows
    }
    if (!pods.hasEarbuds) return rows
    if (effectsView) {
      rows.push("back")
      if (pods.spatialAudioSupported && pods.spatialAudioModeSupported) rows.push("spatial")
      rows.push("default")
      if (pods.spatialAudio) {
        for (var n = 0; n < Model.SPATIAL_EFFECTS.length; n++) rows.push("soundfx:" + Model.SPATIAL_EFFECTS[n])
      } else if (pods.eqOptions.length) rows.push("eqpreset")
      return rows
    }
    for (var i = 0; i < Model.MODES.length; i++) rows.push("mode:" + Model.MODES[i])

    if (pods.ancMode === Model.MODE_NOISE_CANCELING) {
      if (pods.noiseCancelingModeSupported) rows.push("ncmode")
      if (pods.noiseCancelingMode === Model.NC_MODE_MANUAL && pods.manualNoiseCancelingSupported) {
        rows.push("manuallevel")
      }
      if (pods.noiseCancelingMode === Model.NC_MODE_MULTI_SCENE && pods.multiSceneNoiseCancelingSupported) {
        for (var k = 0; k < Model.SCENES.length; k++) rows.push("scene:" + Model.SCENES[k])
      }
      if (pods.realTimeAdaptiveNoiseCancelingSupported) rows.push("realtimeadaptive")
      if (pods.windNoiseSuppressionSupported) rows.push("windnoise")
    } else if (pods.ancMode === Model.MODE_TRANSPARENCY && pods.transparencyModeSupported) {
      for (var m = 0; m < Model.TRANSPARENCY_MODES.length; m++) rows.push("transparency:" + Model.TRANSPARENCY_MODES[m])
    }

    if (hasSoundEffects) rows.push("effects")
    return rows
  }

  readonly property string cursorRow: cursorRows.length === 0
    ? ""
    : cursorRows[Math.max(0, Math.min(cursorIndex, cursorRows.length - 1))]

  function rowHasCursor(name) {
    return cursorActive && cursorRow === name
  }

  function moveCursor(dy) {
    cursorActive = true
    if (cursorRows.length === 0) return
    cursorIndex = Math.max(0, Math.min(cursorRows.length - 1, cursorIndex + dy))
  }

  function activateCursor() {
    var name = cursorRow
    if (name === "") return
    if (name === "installcli" && !pods.cliInstalling) { launchInstaller(); return }
    if (name === "registerdev" && !pods.registering) { pods.registerDevice(registerModelDropdown.value); return }
    if (name === "effects") { showEffects(true); return }
    if (name === "back") { showEffects(false); return }
    if (name === "default") { selectDefault(); return }
    if (name === "spatial") { selectSpatial(); return }
    if (name.indexOf("mode:") === 0) pods.setAncMode(name.substring(5))
    else if (name === "eqpreset") eqPresetDropdown.toggle()
    else if (name === "ncmode") ncModeDropdown.toggle()
    else if (name.indexOf("scene:") === 0) pods.setMultiSceneNoiseCanceling(name.substring(6))
    else if (name.indexOf("transparency:") === 0) pods.setTransparencyMode(name.substring(13))
    else if (name.indexOf("soundfx:") === 0) pods.setSoundEffect(name.substring(8))
    else if (name === "windnoise") pods.setWindNoiseSuppression(!pods.windNoiseSuppression)
    else if (name === "realtimeadaptive") pods.setRealTimeAdaptiveNoiseCanceling(!pods.realTimeAdaptiveNoiseCanceling)
    // "manuallevel" has no single activation — adjusted left/right instead, see onMoveRequested.
  }

  function focusRow(name) {
    var at = cursorRows.indexOf(name)
    if (at < 0) return
    cursorActive = true
    cursorIndex = at
  }

  function launchInstaller() {
    root.close()
    pods.installCli()
  }

  visible: !hideWhenDisconnected || pods.hasEarbuds || pods.cliMissing || pods.registeredMissing || pods.statusStale
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    effectsView = false
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    pods.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: pods
    settings: root.settings
    onHasEarbudsChanged: if (!hasEarbuds) root.showEffects(false)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { pods.refresh(); return "ok" }
    function status(): string { return Model.modeLabel(pods.ancMode) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        SoundcoreIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
        }
      }
    }
    onPressed: function (buttonCode) {
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    // Raised from 460: with per-mode ANC settings and Sound Effects, the panel
    // now regularly grows past what fit when it only showed battery + 3 modes.
    // fittedContentHeight still further clamps this to available screen space,
    // so this is a ceiling, not a fixed size — the Flickable below scrolls
    // anything still taller than that (e.g. Multi-Scene expanded to the max).
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The dropdown owns keys while its popup is open (its own j/k/Enter/Esc
      // handling) — without this our own Keys.priority: BeforeItem would
      // swallow them first and the popup's list would never scroll or close.
      blocked: ncModeDropdown.popupOpen || registerModelDropdown.popupOpen || eqPresetDropdown.popupOpen
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (root.cursorRow === "manuallevel" && dx !== 0) {
          pods.setManualNoiseCancelingLevel(pods.manualNoiseCancelingLevel + dx)
          return
        }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.effectsView ? root.showEffects(false) : root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "r") pods.refresh()
        else if (key === "i" && pods.cliMissing && !pods.cliInstalling) launchInstaller()
        else if (!pods.hasEarbuds || root.effectsView) return
        else if (key === "n") pods.setAncMode(Model.MODE_NOISE_CANCELING)
        else if (key === "t") pods.setAncMode(Model.MODE_TRANSPARENCY)
        else if (key === "o") pods.setAncMode(Model.MODE_NORMAL)
        else if (key === "w" && pods.ancMode === Model.MODE_NOISE_CANCELING && pods.windNoiseSuppressionSupported) pods.setWindNoiseSuppression(!pods.windNoiseSuppression)
      }

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

          PanelHero {
            id: hero
            visible: !root.effectsView
            width: parent.width
            title: pods.cliMissing ? "OpenSCQ30 CLI required" : (pods.registeredMissing ? (pods.unregisteredName || "Soundcore") : (pods.hasEarbuds ? pods.deviceName : "Soundcore"))
            meta: pods.hasEarbuds
              ? Model.modeLabel(pods.ancMode) + (pods.ancMode === Model.MODE_NOISE_CANCELING && pods.noiseCancelingMode !== ""
                  ? " · " + Model.ncSubModeLabel(pods.noiseCancelingMode) : "")
              : pods.cliMissing ? "One-time setup for Omacore"
              : pods.lastError !== "" ? pods.lastError
              : "Checking…"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: pods.hasEarbuds ? 1.0 : 0.5
            iconComponent: Component {
              SoundcoreIcon {
                iconSize: Style.font.display
                color: pods.hasEarbuds ? root.foreground : root.dim
              }
            }
          }

          Column {
            visible: root.opened && pods.cliMissing
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Omacore uses OpenSCQ30 to read and control your Soundcore earbuds. The CLI is not installed on this system."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Install the pinned, hash-verified release in a floating terminal. It stays in your home directory and requires your confirmation before downloading."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              width: parent.width
              text: "Install OpenSCQ30 (opens terminal)"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              hasCursor: root.rowHasCursor("installcli")
              onClicked: launchInstaller()
              onHovered: function (h) { if (h) root.focusRow("installcli") }
            }
          }

          Column {
            visible: root.opened && pods.registeredMissing && !pods.cliMissing
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: pods.unregisteredName + " is paired over Bluetooth, but nothing is registered with OpenSCQ30 yet — the model id in its database also tells this widget which device it is."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: pods.suggestedModel !== ""
              width: parent.width
              text: "Matches the model “" + pods.suggestedModel + "” — registering it automatically."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Dropdown {
              id: registerModelDropdown
              width: parent.width
              showLabel: false
              value: pods.suggestedModel
              options: Model.modelOptions(pods.registerModels)
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.rowHasCursor("registerdev")
              onHovered: function (h) { if (h) root.focusRow("registerdev") }
            }

            Text {
              visible: pods.registering
              width: parent.width
              text: "Registering " + pods.suggestedModel + "…\nThe widget adds the MAC → model entry to OpenSCQ30’s own database; pairing and Bluetooth are untouched."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              visible: !pods.registering
              width: parent.width
              text: "Register this device"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              hasCursor: root.rowHasCursor("registerdev")
              onClicked: pods.registerDevice(registerModelDropdown.value)
              onHovered: function (h) { if (h) root.focusRow("registerdev") }
            }
          }

          Text {
            visible: pods.actionStatus !== ""
            width: parent.width
            text: pods.actionStatus
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: !root.effectsView && pods.hasEarbuds
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "BATTERY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              LevelRow { width: parent.width; label: "Left"; level: pods.leftLevel; charging: pods.leftCharging }
              LevelRow { width: parent.width; label: "Right"; level: pods.rightLevel; charging: pods.rightCharging }
              LevelRow { width: parent.width; label: "Case"; level: pods.caseLevel; charging: false }
            }
          }

          PanelSeparator {
            visible: !root.effectsView && pods.hasEarbuds
            foreground: root.foreground
          }

          Column {
            visible: !root.effectsView && pods.hasEarbuds
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "SOUND MODE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.MODES
                OptionRow {
                  required property var modelData
                  width: parent.width
                  rowName: "mode:" + modelData
                  label: Model.modeLabel(modelData)
                  selected: pods.ancMode === modelData
                  onActivated: pods.setAncMode(modelData)
                }
              }

            }
          }

          PanelSeparator {
            visible: !root.effectsView && pods.hasEarbuds && root.ncSectionVisible
            foreground: root.foreground
          }

          Column {
            visible: !root.effectsView && pods.hasEarbuds && root.ncSectionVisible
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "NOISE CANCELLING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              RowLayout {
                width: parent.width
                visible: pods.noiseCancelingModeSupported
                spacing: Style.space(8)

                Text {
                  text: "Mode"
                  color: root.foreground
                  opacity: 0.75
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  Layout.preferredWidth: Style.space(50)
                }

                Dropdown {
                  id: ncModeDropdown
                  Layout.fillWidth: true
                  showLabel: false
                  value: pods.noiseCancelingMode
                  options: root.ncModeOptions
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.rowHasCursor("ncmode")
                  onChanged: function (v) { pods.setNoiseCancelingMode(v) }
                  onHovered: function (h) { if (h) root.focusRow("ncmode") }

                  // Selecting an option assigns Dropdown.value directly, which breaks
                  // the binding above — this keeps it following pods's state
                  // (settled/confirmed writes, or an external change) afterward.
                  Binding {
                    target: ncModeDropdown
                    property: "value"
                    value: pods.noiseCancelingMode
                  }
                }

              }

              ManualLevelRow {
                visible: pods.noiseCancelingMode === Model.NC_MODE_MANUAL && pods.manualNoiseCancelingSupported
                width: parent.width
              }

              Row {
                id: sceneRow
                visible: pods.noiseCancelingMode === Model.NC_MODE_MULTI_SCENE && pods.multiSceneNoiseCancelingSupported
                width: parent.width
                spacing: Style.space(6)

                readonly property real cellWidth: Model.SCENES.length > 0
                  ? (width - spacing * (Model.SCENES.length - 1)) / Model.SCENES.length
                  : 0

                Repeater {
                  model: Model.SCENES
                  Button {
                    required property var modelData
                    width: sceneRow.cellWidth
                    text: Model.sceneLabel(modelData)
                    fontSize: Style.font.bodySmall
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                    bordered: true
                    active: pods.multiSceneNoiseCanceling === modelData
                    hasCursor: root.rowHasCursor("scene:" + modelData)
                    onClicked: pods.setMultiSceneNoiseCanceling(modelData)
                    onHovered: function (h) { if (h) root.focusRow("scene:" + modelData) }
                  }
                }
              }

              // Independent of noiseCancelingMode, same as Soundcore's own app.
              // Placed directly above Wind Noise Suppression so the two
              // toggles always sit together, regardless of which mode-specific
              // row (manual level / multi-scene) is showing above them.
              ToggleRow {
                visible: pods.realTimeAdaptiveNoiseCancelingSupported
                width: parent.width
                rowName: "realtimeadaptive"
                label: "Real-time Adaptive ANC"
                on: pods.realTimeAdaptiveNoiseCanceling
                onActivated: pods.setRealTimeAdaptiveNoiseCanceling(!pods.realTimeAdaptiveNoiseCanceling)
              }

              ToggleRow {
                visible: pods.windNoiseSuppressionSupported
                width: parent.width
                rowName: "windnoise"
                label: "Wind Noise Suppression"
                on: pods.windNoiseSuppression
                onActivated: pods.setWindNoiseSuppression(!pods.windNoiseSuppression)
              }
            }
          }

          PanelSeparator {
            visible: !root.effectsView && pods.hasEarbuds && root.transparencySectionVisible
            foreground: root.foreground
          }

          Column {
            visible: !root.effectsView && pods.hasEarbuds && root.transparencySectionVisible
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "TRANSPARENCY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.TRANSPARENCY_MODES
                OptionRow {
                  required property var modelData
                  width: parent.width
                  rowName: "transparency:" + modelData
                  label: Model.transparencyModeLabel(modelData)
                  selected: pods.transparencyMode === modelData
                  onActivated: pods.setTransparencyMode(modelData)
                }
              }
            }
          }

          PanelSeparator {
            visible: !root.effectsView && pods.hasEarbuds && root.hasSoundEffects
            foreground: root.foreground
          }

          NavigationRow {
            visible: !root.effectsView && pods.hasEarbuds && root.hasSoundEffects
            width: parent.width
            rowName: "effects"
            title: "Sound Effects"
            subtitle: root.effectsSummary
            onActivated: root.showEffects(true)
          }

          Column {
            visible: root.effectsView && pods.hasEarbuds
            width: parent.width
            spacing: Style.space(12)

            CursorSurface {
              implicitWidth: backContent.implicitWidth + Style.space(16)
              implicitHeight: backContent.implicitHeight + Style.space(12)
              foreground: root.foreground
              hasCursor: root.rowHasCursor("back")
              RowLayout {
                id: backContent
                anchors.centerIn: parent
                spacing: Style.space(10)
                Canvas {
                  Layout.alignment: Qt.AlignVCenter
                  implicitWidth: Style.space(12)
                  implicitHeight: Style.space(22)
                  property color ink: root.foreground
                  onInkChanged: requestPaint()
                  onWidthChanged: requestPaint()
                  onHeightChanged: requestPaint()
                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = ink
                    ctx.lineWidth = Style.space(2)
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(width * 0.75, height * 0.2)
                    ctx.lineTo(width * 0.25, height * 0.5)
                    ctx.lineTo(width * 0.75, height * 0.8)
                    ctx.stroke()
                  }
                }
                Text {
                  Layout.alignment: Qt.AlignVCenter
                  text: "Back to earbuds"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.focusRow("back")
                onClicked: root.showEffects(false)
              }
            }

            PanelSectionHeader {
              width: parent.width
              text: "SOUND EFFECTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              OptionRow {
                visible: pods.spatialAudioSupported && pods.spatialAudioModeSupported
                width: parent.width
                rowName: "spatial"
                label: "Spatial Audio"
                selected: pods.spatialAudio
                onActivated: root.selectSpatial()
              }
              OptionRow {
                width: parent.width
                rowName: "default"
                label: "Default"
                selected: !pods.spatialAudio
                onActivated: root.selectDefault()
              }
            }

            PanelSeparator { foreground: root.foreground }

            Column {
              visible: !pods.spatialAudio && pods.eqOptions.length > 0
              width: parent.width
              spacing: Style.space(10)
              PanelSectionHeader {
                text: "EQ PRESET"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              RowLayout {
                width: parent.width
                spacing: Style.space(8)
                Dropdown {
                  id: eqPresetDropdown
                  Layout.fillWidth: true
                  showLabel: false
                  value: pods.eqPreset || "Custom EQ"
                  options: pods.eqOptions
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.rowHasCursor("eqpreset")
                  onChanged: function (v) { pods.setEqPreset(v) }
                  onHovered: function (h) { if (h) root.focusRow("eqpreset") }
                  Binding {
                    target: eqPresetDropdown
                    property: "value"
                    value: pods.eqPreset || "Custom EQ"
                  }
                }

              }
            }

            Column {
              visible: pods.spatialAudio && pods.spatialAudioModeSupported
              width: parent.width
              spacing: Style.space(6)
              PanelSectionHeader {
                text: "SPATIAL AUDIO MODE"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Row {
                id: spatialModeRow
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: Model.SPATIAL_EFFECTS
                  Button {
                    required property var modelData
                    width: (spatialModeRow.width - spatialModeRow.spacing * (Model.SPATIAL_EFFECTS.length - 1)) / Model.SPATIAL_EFFECTS.length
                    text: Model.soundEffectLabel(modelData)
                    fontSize: Style.font.bodySmall
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    bordered: true
                    active: pods.spatialAudioMode === modelData
                    hasCursor: root.rowHasCursor("soundfx:" + modelData)
                    onClicked: pods.setSoundEffect(modelData)
                    onHovered: function (h) { if (h) root.focusRow("soundfx:" + modelData) }
                  }
                }
              }
            }
          }

          Text {
            visible: root.guidanceVisible
            width: parent.width
            text: pods.lastError
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }

    }
  }

  component NavigationRow: CursorSurface {
    id: nav
    property string rowName: ""
    property string title: ""
    property string subtitle: ""
    property bool back: false
    signal activated()
    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: navText.implicitHeight + Style.space(16)
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(nav.rowName)
      onClicked: nav.activated()
    }
    RowLayout {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(10)
      Text {
        visible: nav.back
        text: "‹"
        font.pixelSize: Style.font.display
        color: root.foreground
      }
      Column {
        id: navText
        Layout.fillWidth: true
        spacing: Style.space(4)
        Text {
          width: parent.width
          text: nav.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: nav.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Text {
        visible: !nav.back
        text: "›"
        font.pixelSize: Style.font.display
        color: root.foreground
      }
    }
  }

  component LevelRow: Item {
    id: levelRow
    property string label: ""
    property int level: Model.LEVEL_UNKNOWN
    property bool charging: false

    readonly property bool low: level !== Model.LEVEL_UNKNOWN && level <= pods.lowBatteryPercent && !charging

    implicitHeight: levelLayout.implicitHeight

    RowLayout {
      id: levelLayout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(8)

      Text {
        text: levelRow.label
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Style.space(44)
      }

      Rectangle {
        id: meterTrack
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: Style.space(6)
        radius: height / 2
        color: Qt.darker(root.foreground, 3.2)

        Rectangle {
          width: meterTrack.width * Model.levelFraction(levelRow.level)
          height: parent.height
          radius: parent.radius
          color: levelRow.low ? root.urgent : root.foreground
        }
      }

      Text {
        text: Model.levelText(levelRow.level)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Style.space(38)
      }

      Text {
        text: levelRow.charging ? "Charging" : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Layout.preferredWidth: Style.space(56)
      }
    }
  }

  // Generic checkmark-list row, reused for ambient sound mode, ANC sub-mode,
  // multi-scene, transparency mode and sound effects — every setting in this
  // panel where the widget picks exactly one value out of a fixed list.
  component OptionRow: CursorSurface {
    id: optionRow
    property string rowName: ""
    property string label: ""
    property bool selected: false
    signal activated()

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: optionLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(optionRow.rowName)
      onClicked: optionRow.activated()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        id: optionLabel
        Layout.fillWidth: true
        text: optionRow.label
        color: root.foreground
        opacity: optionRow.selected ? 1.0 : 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        Layout.alignment: Qt.AlignVCenter
        text: "󰄬"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        opacity: optionRow.selected ? 1.0 : 0.0
      }
    }
  }

  // Generic toggle row, reused for wind noise suppression and real-time adaptive ANC.
  component ToggleRow: CursorSurface {
    id: toggleRow
    property string rowName: ""
    property string label: ""
    property bool on: false
    signal activated()

    // Unlike the checkmark-list rows, only the switch itself is
    // clickable/hoverable — the row surface never paints a cursor fill/border
    // of its own, so hovering the label doesn't light up the whole row. The
    // switch shows its own compact cursor ring instead (below).
    foreground: root.foreground
    implicitHeight: Math.max(toggleLabel.implicitHeight, toggleSwitch.implicitHeight)

    // Flush with the Mode row above — no row background to pad out to here.
    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        id: toggleLabel
        Layout.fillWidth: true
        text: toggleRow.label
        color: root.foreground
        opacity: toggleRow.on ? 1.0 : 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      ToggleSwitch {
        id: toggleSwitch
        Layout.alignment: Qt.AlignVCenter
        trackHeight: Math.round(toggleLabel.font.pixelSize * 1.2)
        checked: toggleRow.on
        interactive: false
        cursorRing: true
        hasCursor: root.rowHasCursor(toggleRow.rowName)
        foreground: root.foreground

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.focusRow(toggleRow.rowName)
          onClicked: toggleRow.activated()
        }
      }
    }
  }

  // manualNoiseCanceling's 1-5 intensity level: click a segment to jump straight
  // to it, or move the keyboard cursor here and use left/right to step by one.
  component ManualLevelRow: CursorSurface {
    id: levelRow

    readonly property string rowName: "manuallevel"
    readonly property int level: pods.manualNoiseCancelingLevel

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: levelLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: root.focusRow(levelRow.rowName)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        id: levelLabel
        text: "Level"
        color: root.foreground
        opacity: 0.75
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.preferredWidth: Style.space(44)
      }

      Row {
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(4)

        Repeater {
          model: Model.MANUAL_LEVEL_MAX
          Rectangle {
            required property int index
            readonly property int segmentLevel: index + 1
            width: Style.space(22)
            height: Style.space(10)
            radius: Style.space(2)
            color: segmentLevel <= levelRow.level ? root.foreground : Qt.darker(root.foreground, 3.2)

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.focusRow(levelRow.rowName); pods.setManualNoiseCancelingLevel(segmentLevel) }
            }
          }
        }
      }

      Item { Layout.fillWidth: true }

      Text {
        text: levelRow.level > 0 ? String(levelRow.level) : "--"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Style.space(16)
        horizontalAlignment: Text.AlignRight
      }
    }
  }
}
