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

  readonly property color soundAccent: Color.accent
  readonly property var homeModes: [Model.MODE_NOISE_CANCELING, Model.MODE_NORMAL, Model.MODE_TRANSPARENCY]
  property int cursorIndex: 0
  property bool cursorActive: false
  property bool effectsView: false
  property bool dualView: false
  property bool settingsView: false
  property string settingsDetail: ""
  property bool buttonsView: false
  property string selectedGesture: ""
  property bool resetButtonsArmed: false
  property bool importEqArmed: false
  readonly property bool mainView: !effectsView && !dualView && !settingsView && !buttonsView
  readonly property var selectedGestureInfo: Model.BUTTON_GESTURES.find(function (gesture) { return gesture.id === selectedGesture }) || ({ side: "", label: "" })
  property bool manageHistory: false
  readonly property var currentDevices: pods.dualConnectionsDevices.map(function (mac) {
    var option = pods.dualConnectionsOptions.find(function (o) { return o.value === mac })
    return option || { value: mac, label: mac }
  })
  readonly property var historyDevices: pods.dualConnectionsOptions.filter(function (o) {
    return pods.dualConnectionsDevices.indexOf(o.value) < 0
  })
  readonly property bool hasSoundEffects: pods.customEqSupported || pods.eqOptions.length > 0 || (pods.spatialAudioSupported && pods.spatialAudioModeSupported)
  readonly property bool devicePickerVisible: mainView && !pods.cliMissing && !pods.registeredMissing &&
    (pods.availableDevices.length > 1 || (!pods.hasEarbuds && pods.deviceMatch !== ""))
  readonly property var deviceOptions: [{ value: "", label: "Automatic" }].concat(pods.availableDevices.map(function (device) {
    return { value: device.mac, label: device.name + " · " + device.mac.slice(-5) }
  }))
  readonly property string devicePickerValue: {
    if (pods.deviceMatch === "") return ""
    var match = pods.deviceMatch.toLowerCase()
    for (var i = 0; i < pods.availableDevices.length; i++) {
      var device = pods.availableDevices[i]
      if (device.mac.toLowerCase().indexOf(match) >= 0 || device.name.toLowerCase().indexOf(match) >= 0) return device.mac
    }
    return pods.deviceMatch
  }
  readonly property string effectsSummary: {
    if (pods.spatialAudio) return "Spatial Audio · " + Model.soundEffectLabel(pods.spatialAudioMode)
    if (pods.customEqActive) return "Custom EQ" + (pods.customEqProfile ? " · " + pods.customEqProfile : "")
    for (var i = 0; i < pods.eqOptions.length; i++) {
      if (pods.eqOptions[i].value === pods.eqPreset) return "Default · " + pods.eqOptions[i].label
    }
    return pods.eqOptions.length ? "Custom EQ" : "Default"
  }

  property var pageScroll: ({})
  readonly property string pageKey: effectsView ? "effects" : dualView ? "dual" : buttonsView ? "buttons/" + selectedGesture : settingsView ? "settings/" + settingsDetail : "main"

  function navigate(page, detail) {
    pageScroll[pageKey] = panelFlick.contentY
    deviceDropdown.close()
    ncModeDropdown.close()
    eqPresetDropdown.close()
    customEditor.closeEditors()
    effectsView = page === "effects"
    dualView = page === "dual"
    settingsView = page === "settings"
    buttonsView = page === "buttons"
    settingsDetail = settingsView ? (detail || "") : ""
    selectedGesture = buttonsView ? (detail || "") : ""
    resetButtonsArmed = false
    importEqArmed = false
    manageHistory = false
    cursorActive = false
    cursorIndex = 0
    var scroll = pageScroll[pageKey] || 0
    panelFlick.contentY = 0
    Qt.callLater(function () {
      panelFlick.contentY = Math.max(0, Math.min(scroll, panelFlick.contentHeight - panelFlick.height))
      keyCatcher.forceActiveFocus()
    })
  }

  function showEffects(show) { navigate(show ? "effects" : "main") }
  function showDual(show) { navigate(show ? "dual" : "settings") }
  function showSettings(show) { navigate(show ? "settings" : "main") }
  function showDetail(detail) { navigate("settings", detail) }
  function showHighVolume() { if (pods.limitHighVolumeSupported) showDetail("volume") }
  function showDeviceInfo() { showDetail("info") }

  readonly property var deviceInfoRows: [
    { label: "Model", value: pods.deviceModel },
    { label: "Left firmware", value: pods.deviceInfo.firmwareLeft || "" },
    { label: "Right firmware", value: pods.deviceInfo.firmwareRight || "" },
    { label: "Serial number", value: pods.deviceInfo.serial || "" },
    { label: "Earbud connection", value: pods.deviceInfo.tws || "" },
    { label: "Primary earbud", value: pods.deviceInfo.host || "" },
    { label: "Wind detected", value: pods.deviceInfo.wind === "true" ? "Yes" : pods.deviceInfo.wind === "false" ? "No" : pods.deviceInfo.wind || "" },
    { label: "Adaptive ANC", value: pods.deviceInfo.adaptive || "" }
  ].filter(function (row) { return row.value !== "" })

  function showButtons(show) { navigate(show ? "buttons" : "settings") }

  function showGesture(id) {
    if (!pods.buttonOptions[id] || !pods.buttonOptions[id].length) return
    navigate("buttons", id)
  }

  function confirmResetButtons() {
    if (!pods.buttonResetSupported || !pods.hasButtonControls) return
    if (!resetButtonsArmed) { resetButtonsArmed = true; return }
    resetButtonsArmed = false
    pods.resetButtonBindings()
  }

  function goBack() {
    if (buttonsView && selectedGesture !== "") { showButtons(true); return }
    if (buttonsView) { showButtons(false); return }
    if (settingsView && (settingsDetail === "volume" || settingsDetail === "power")) { showDetail("preferences"); return }
    if (settingsView && settingsDetail !== "") { showSettings(true); return }
    if (settingsView) { showSettings(false); return }
    if (dualView) { showDual(false); return }
    if (effectsView) { showEffects(false); return }
    close()
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

  function importEq() {
    if (!importEqArmed) { importEqArmed = true; return }
    importEqArmed = false
    pods.transferEq("import")
  }

  readonly property bool hideWhenDisconnected: setting("hideWhenDisconnected", true) === true
  readonly property bool showBatteryPercent: setting("showBatteryPercent", true) === true
  readonly property int barBatteryLevel: Model.barBatteryLevel(pods.leftLevel, pods.rightLevel, pods.caseLevel)
  property int pendingBatteryDisplay: -1
  readonly property int batteryDisplayMode: pendingBatteryDisplay >= 0 ? pendingBatteryDisplay : Model.batteryDisplayMode(setting("batteryDisplayMode", showBatteryPercent ? 1 : 0))
  readonly property bool barBatteryVisible: batteryDisplayMode !== 0 && pods.hasEarbuds
  readonly property string barBatteryText: Model.barBatteryText(batteryDisplayMode, pods.leftLevel, pods.rightLevel, pods.caseLevel)
  TextMetrics { id: batteryTextMetrics; text: root.batteryDisplayMode === 2 ? [pods.leftLevel, pods.rightLevel, pods.caseLevel].map(function (level) { return level < 0 ? "—" : level + "%" }).join("") : root.barBatteryText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  // A missing CLI or an unregistered-but-connected device are both worth
  // showing as an alert in the bar even when the buds are (as a result)
  // unreachable — a broken setup should be loud, not invisible.
  readonly property color barIconColor: (pods.cliMissing || pods.registeredMissing) ? urgent
    : (pods.hasEarbuds ? (barBatteryLevel >= 0 && barBatteryLevel <= pods.lowBatteryPercent ? urgent : barForeground) : Qt.darker(barForeground, 1.55))
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
    if (devicePickerVisible) rows.push("device")
    if (!pods.hasEarbuds) return rows
    if (effectsView) {
      rows.push("back")
      if (pods.spatialAudioSupported && pods.spatialAudioModeSupported) rows.push("spatial")
      rows.push("default")
      if (pods.customEqSupported) rows.push("custom")
      if (pods.spatialAudio) {
        for (var n = 0; n < Model.SPATIAL_EFFECTS.length; n++) rows.push("soundfx:" + Model.SPATIAL_EFFECTS[n])
      } else if (pods.customEqActive) {
        if (pods.customEqOptions.length) rows.push("customsaved")
        for (var band = 0; band < pods.eqBands.length; band++) rows.push("eqband:" + band)
        rows.push("customflat")
        if (pods.customEqProfilesSupported) { rows.push("customname"); rows.push("customsave") }
      } else if (pods.eqOptions.length) rows.push("eqpreset")
      return rows
    }
    if (settingsView) {
      rows.push("back")
      if (settingsDetail === "volume") {
        rows.push("volumetoggle")
        for (var v = 0; v < pods.limitDbOptions.length; v++) rows.push("volumedb:" + pods.limitDbOptions[v].value)
        for (var r = 0; r < pods.limitRateOptions.length; r++) rows.push("volumerate:" + pods.limitRateOptions[r].value)
      } else if (settingsDetail === "") {
        if (pods.ldacSupported || pods.hostCodec !== "") rows.push("detail:audio")
        if (pods.dualConnectionsSupported) rows.push("dual")
        if (pods.hasButtonControls) rows.push("buttons")
        if (pods.autoPowerOffSupported || pods.touchToneSupported || pods.lowBatteryPromptSupported || pods.limitHighVolumeSupported) rows.push("detail:preferences")
        if (pods.eqTransferSupported) rows.push("detail:transfer")
        if (deviceInfoRows.length > 0) rows.push("detail:info")
      } else if (settingsDetail === "preferences") {
        if (pods.autoPowerOffSupported && pods.autoPowerOffOptions.length) rows.push("detail:power")
        if (pods.touchToneSupported) rows.push("touchtone")
        if (pods.lowBatteryPromptSupported) rows.push("lowprompt")
        if (pods.limitHighVolumeSupported) rows.push("volumesettings")
      } else if (settingsDetail === "power") {
        for (var p = 0; p < pods.autoPowerOffOptions.length; p++) rows.push("power:" + pods.autoPowerOffOptions[p].value)
      } else if (settingsDetail === "audio") {
        if (pods.ldacSupported) rows.push("ldac")
      } else if (settingsDetail === "transfer") {
        if (pods.customEqOptions.length) rows.push("eqexport")
        rows.push("eqimport")

      }
      return rows
    }
    if (buttonsView) {
      rows.push("back")
      if (selectedGesture !== "") {
        var choices = pods.buttonOptions[selectedGesture] || []
        for (var b = 0; b < choices.length; b++) rows.push("buttonoption:" + choices[b].value)
      } else {
        for (var g = 0; g < Model.BUTTON_GESTURES.length; g++) {
          var id = Model.BUTTON_GESTURES[g].id
          if (pods.buttonOptions[id] && pods.buttonOptions[id].length) rows.push("button:" + id)
        }
        if (pods.buttonResetSupported) rows.push("resetbuttons")
      }
      return rows
    }
    if (dualView) {
      rows.push("back")
      if (pods.dualConnectionsSupported) rows.push("dualtoggle")
      if (pods.dualConnections && pods.dualConnectionsDevicesSupported) {
        for (var d = 0; d < currentDevices.length; d++) rows.push("currentdevice:" + currentDevices[d].value)
        if (historyDevices.length) rows.push("dualmanage")
        for (var h = 0; h < historyDevices.length; h++)
          rows.push((manageHistory ? "forgetdevice:" : "historydevice:") + historyDevices[h].value)
      }
      return rows
    }
    rows.push("settings")
    for (var i = 0; i < homeModes.length; i++) rows.push("mode:" + homeModes[i])
    if (ncSectionVisible) {
        if (pods.noiseCancelingModeSupported) rows.push("ncmode")
        if (pods.noiseCancelingMode === Model.NC_MODE_MANUAL && pods.manualNoiseCancelingSupported) rows.push("manuallevel")
        if (pods.noiseCancelingMode === Model.NC_MODE_MULTI_SCENE && pods.multiSceneNoiseCancelingSupported)
          for (var k = 0; k < Model.SCENES.length; k++) rows.push("scene:" + Model.SCENES[k])
        if (pods.realTimeAdaptiveNoiseCancelingSupported) rows.push("realtimeadaptive")
        if (pods.windNoiseSuppressionSupported) rows.push("windnoise")
    }
    if (transparencySectionVisible)
      for (var m = 0; m < Model.TRANSPARENCY_MODES.length; m++) rows.push("transparency:" + Model.TRANSPARENCY_MODES[m])
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
    Qt.callLater(revealCursor)
  }

  function findCursorItem(parentItem, name) {
    if (!parentItem || !parentItem.visible) return null
    if (parentItem.visible && parentItem.rowName === name) return parentItem
    for (var i = 0; i < parentItem.children.length; i++) {
      var found = findCursorItem(parentItem.children[i], name)
      if (found) return found
    }
    return null
  }

  function revealCursor() {
    if (!cursorActive || !panelFlick || !column) return
    var item = findCursorItem(column, cursorRow)
    if (!item) return
    var top = item.mapToItem(column, 0, 0).y
    var bottom = top + item.height
    if (top < panelFlick.contentY) panelFlick.contentY = top
    else if (bottom > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.max(0, Math.min(panelFlick.contentHeight - panelFlick.height, bottom - panelFlick.height))
  }

  function activateCursor() {
    var name = cursorRow
    if (name === "") return
    if (name === "installcli" && !pods.cliInstalling) { launchInstaller(); return }
    if (name === "registerdev" && !pods.registering) { pods.registerDevice(registerModelDropdown.value); return }
    if (name.indexOf("detail:") === 0) { showDetail(name.substring(7)); return }
    if (name === "device") { deviceDropdown.toggle(); return }
    if (name === "effects") { showEffects(true); return }
    if (name === "dual") { showDual(true); return }
    if (name === "settings") { showSettings(true); return }
    if (name === "buttons") { showButtons(true); return }
    if (name === "back") { goBack(); return }
    if (name === "volumesettings") { showHighVolume(); return }
    if (name === "deviceinfo") { showDeviceInfo(); return }
    if (name === "touchtone") { pods.setTouchTone(!pods.touchTone); return }
    if (name === "lowprompt") { pods.setLowBatteryPrompt(!pods.lowBatteryPrompt); return }
    if (name === "volumetoggle") { pods.setHighVolumeLimit(!pods.limitHighVolume); return }
    if (name.indexOf("volumedb:") === 0) { pods.setLimitDb(Number(name.substring(9))); return }
    if (name.indexOf("volumerate:") === 0) { pods.setLimitRate(name.substring(11)); return }
    if (name.indexOf("button:") === 0) { showGesture(name.substring(7)); return }
    if (name.indexOf("buttonoption:") === 0) { pods.setButtonBinding(selectedGesture, name.substring(13)); return }
    if (name === "resetbuttons") { confirmResetButtons(); return }
    if (name.indexOf("power:") === 0) { pods.setAutoPowerOff(name.substring(6)); return }
    if (name === "dualtoggle") { pods.setDualConnections(!pods.dualConnections); return }
    if (name === "dualmanage") { manageHistory = !manageHistory; return }
    if (name.indexOf("currentdevice:") === 0) { pods.setDeviceConnection(name.substring(14), false); return }
    if (name.indexOf("historydevice:") === 0) { pods.setDeviceConnection(name.substring(14), true); return }
    if (name.indexOf("forgetdevice:") === 0 && manageHistory) { pods.removeDualConnectionsDevice(name.substring(13)); return }
    if (name === "default") { selectDefault(); return }
    if (name === "spatial") { selectSpatial(); return }
    if (name === "custom") { pods.setCustomEqBands(pods.eqBands); return }
    if (name === "eqexport") { pods.transferEq("export"); return }
    if (name === "eqimport") { importEq(); return }
    if (name.indexOf("custom") === 0) { customEditor.activate(name); return }
    if (name.indexOf("mode:") === 0) pods.setAncMode(name.substring(5))
    else if (name === "eqpreset") eqPresetDropdown.toggle()
    else if (name === "ncmode") ncModeDropdown.toggle()
    else if (name.indexOf("scene:") === 0) pods.setMultiSceneNoiseCanceling(name.substring(6))
    else if (name.indexOf("transparency:") === 0) pods.setTransparencyMode(name.substring(13))
    else if (name.indexOf("soundfx:") === 0) pods.setSoundEffect(name.substring(8))
    else if (name === "windnoise") pods.setWindNoiseSuppression(!pods.windNoiseSuppression)
    else if (name === "ldac") pods.setLdac(!pods.ldacEnabled)
    else if (name === "realtimeadaptive") pods.setRealTimeAdaptiveNoiseCanceling(!pods.realTimeAdaptiveNoiseCanceling)
    // "manuallevel" has no single activation — adjusted left/right instead, see onMoveRequested.
  }

  function focusRow(name) {
    var at = cursorRows.indexOf(name)
    if (at < 0) return
    cursorActive = true
    cursorIndex = at
    Qt.callLater(revealCursor)
  }

  function launchInstaller() {
    root.close()
    pods.installCli()
  }

  function cycleBatteryDisplay() {
    if (batteryDisplaySave.running) return
    pendingBatteryDisplay = (batteryDisplayMode + 1) % 3
    batteryDisplaySave.command = ["omarchy", "bar", "set", root.moduleName, "batteryDisplayMode", String(pendingBatteryDisplay), "--json"]
    batteryDisplaySave.running = true
  }

  Process {
    id: batteryDisplaySave
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.pendingBatteryDisplay = -1
        pods.actionStatusError = true
        pods.actionStatus = "Could not save battery display preference."
      }
    }
  }
  onSettingsChanged: pendingBatteryDisplay = -1

  visible: !hideWhenDisconnected || pods.hasEarbuds || pods.cliMissing || pods.registeredMissing || pods.statusStale || pods.availableDevices.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    pageScroll = ({})
    effectsView = false
    dualView = false
    settingsView = false
    settingsDetail = ""
    buttonsView = false
    selectedGesture = ""
    resetButtonsArmed = false
    importEqArmed = false
    manageHistory = false
    cursorActive = false
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    pods.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: pods
    settings: root.settings
    liveUpdates: root.opened && root.dualView
    panelOpen: root.opened
    onHasEarbudsChanged: if (!hasEarbuds) root.showEffects(false)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function cycleBatteryDisplay(): void { root.cycleBatteryDisplay() }
    function openSettings(page: string): void {
      var pages = ["", "audio", "preferences", "power", "volume", "transfer", "info"]
      if (pages.indexOf(page) < 0) return
      root.open()
      root.showDetail(page)
    }
    function openDual(): void { root.open(); root.showDual(true) }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { pods.refresh(); return "ok" }
    function status(): string { return Model.modeLabel(pods.ancMode) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barBatteryVisible ? (bar && bar.vertical ? Style.space(root.batteryDisplayMode === 2 ? 72 : 42) : batteryTextMetrics.width + Style.space(root.batteryDisplayMode === 2 ? 82 : 30)) : Style.bar.iconSlot
    opticalSize: slotSize
    tooltipText: ""
    iconComponent: Component {
      Item {
        GridLayout {
          anchors.centerIn: parent
          columns: bar && bar.vertical ? 1 : 2
          rowSpacing: Style.space(4)
          columnSpacing: Style.space(4)
          SoundcoreIcon {
            visible: !root.barBatteryVisible || root.batteryDisplayMode !== 2
            Layout.alignment: Qt.AlignCenter
            // Align the drawing with the visible digits rather than the font's line box.
            transform: Translate { y: root.barBatteryVisible && root.batteryDisplayMode === 1 ? -Style.space(1) : 0 }
            iconSize: Style.space(12)
            color: root.barIconColor
          }
          Text {
            visible: root.barBatteryVisible && root.batteryDisplayMode === 1
            Layout.alignment: Qt.AlignCenter
            text: root.barBatteryText
            color: root.barIconColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          GridLayout {
            visible: root.barBatteryVisible && root.batteryDisplayMode === 2
            Layout.alignment: Qt.AlignCenter
            columns: bar && bar.vertical ? 1 : 3
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(4)
            Repeater {
              model: [{kind: "left", level: pods.leftLevel}, {kind: "right", level: pods.rightLevel}, {kind: "case", level: pods.caseLevel}]
              RowLayout {
                required property var modelData
                Layout.alignment: Qt.AlignCenter
                spacing: Style.space(3)
                ControlIcon {
                  Layout.alignment: Qt.AlignVCenter
                  Layout.preferredWidth: Style.space(16)
                  Layout.preferredHeight: Style.space(16)
                  kind: modelData.kind
                  ink: root.barIconColor
                }
                Text {
                  Layout.alignment: Qt.AlignVCenter
                  text: modelData.level < 0 ? "—" : modelData.level + "%"
                  color: root.barIconColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) root.cycleBatteryDisplay()
      else root.toggle()
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The dropdown owns keys while its popup is open (its own j/k/Enter/Esc
      // handling) — without this our own Keys.priority: BeforeItem would
      // swallow them first and the popup's list would never scroll or close.
    blocked: deviceDropdown.popupOpen || ncModeDropdown.popupOpen || registerModelDropdown.popupOpen || eqPresetDropdown.popupOpen || customEditor.popupOpen || customEditor.inputFocused
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (root.cursorRow.indexOf("eqband:") === 0 && dx !== 0) {
          customEditor.adjust(Number(root.cursorRow.substring(7)), dx)
          return
        }
        if (root.cursorRow === "manuallevel" && dx !== 0) {
          pods.setManualNoiseCancelingLevel(pods.manualNoiseCancelingLevel + dx)
          return
        }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.goBack()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        if (key === "r") pods.refresh()
        else if (key === "i" && pods.cliMissing && !pods.cliInstalling) launchInstaller()
        else if (!pods.hasEarbuds || !root.mainView) return
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

          RowLayout {
            visible: root.mainView
            width: parent.width
            spacing: Style.space(8)
          PanelHero {
            id: hero
            Layout.fillWidth: true
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

            PanelActionButton {
              property string rowName: "settings"
              visible: pods.hasEarbuds
              iconText: "󰒓"
              tooltipText: "Advanced Settings"
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.rowHasCursor("settings")
              onHovered: function (h) { if (h) root.focusRow("settings") }
              onClicked: root.showSettings(true)
            }
          }

          RowLayout {
            visible: root.devicePickerVisible
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Device"
              color: root.foreground
              opacity: 0.75
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              Layout.preferredWidth: Style.space(50)
            }

            Dropdown {
              id: deviceDropdown
              Layout.fillWidth: true
              showLabel: false
              value: root.devicePickerValue
              options: root.deviceOptions
              enabled: !pods.busy && !pods.updating && !pods.choosingDevice
              foreground: root.foreground
              fontFamily: root.fontFamily
              hasCursor: root.rowHasCursor("device")
              onChanged: function (v) { pods.chooseDevice(v) }
              onHovered: function (h) { if (h) root.focusRow("device") }
              Binding {
                target: deviceDropdown
                property: "value"
                value: root.devicePickerValue
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
            color: pods.actionStatusError ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSectionHeader {
            visible: root.mainView && pods.hasEarbuds
            text: "BATTERY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            visible: root.mainView && pods.hasEarbuds
            width: parent.width
            spacing: Style.space(8)
            BatteryCell { width: parent.width; label: "Left"; level: pods.leftLevel; charging: pods.leftCharging }
            BatteryCell { width: parent.width; label: "Right"; level: pods.rightLevel; charging: pods.rightCharging }
            BatteryCell { width: parent.width; label: "Case"; level: pods.caseLevel }
          }

          PanelSeparator {
            visible: root.mainView && pods.hasEarbuds
            foreground: root.foreground
          }

          Column {
            visible: root.mainView && pods.hasEarbuds
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "SOUND MODE"
              foreground: root.foreground
              fontFamily: root.fontFamily
              MouseArea { id: modeHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
              PanelToolTip { visible: modeHelp.containsMouse; text: "n ANC · t Transparency · o Normal\nw Wind (ANC) · r Refresh · Esc Back"; fontFamily: root.fontFamily }
            }

            Row {
              id: soundModeRow
              width: parent.width
              spacing: Style.space(4)
              Repeater {
                model: root.homeModes
                CursorSurface {
                  id: modeTile
                  required property var modelData
                  property string rowName: "mode:" + modelData
                  width: (soundModeRow.width - soundModeRow.spacing * 2) / 3
                  implicitHeight: Style.space(86)
                  foreground: root.foreground
                  bordered: false
                  color: "transparent"
                  borderSpec: Border.none()
                  current: pods.ancMode === modelData
                  hasCursor: root.rowHasCursor(rowName)
                  Accessible.role: Accessible.RadioButton
                  Accessible.name: Model.modeLabel(modelData)
                  Accessible.checked: current
                  Column {
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(10)
                    width: parent.width
                    spacing: Style.space(8)
                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: Style.space(48); height: width; radius: width / 2
                      color: modeTile.current ? root.soundAccent : Qt.tint(Color.background, Qt.alpha(root.foreground, 0.10))
                      border.width: modeTile.hasCursor ? 1 : 0
                      border.color: root.foreground
                      ControlIcon {
                        anchors.centerIn: parent
                        width: Style.space(29); height: width
                        kind: modeTile.modelData === Model.MODE_TRANSPARENCY ? "transparency" : modeTile.modelData === Model.MODE_NOISE_CANCELING ? "anc" : "normal"
                        ink: modeTile.current ? Color.background : root.foreground
                      }
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                      text: modeTile.modelData === Model.MODE_NOISE_CANCELING ? "ANC" : Model.modeLabel(modeTile.modelData)
                      color: modeTile.current ? root.foreground : Qt.alpha(root.foreground, 0.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.focusRow(modeTile.rowName)
                    onClicked: pods.setAncMode(modeTile.modelData)
                  }
                }
              }
            }
          }

          PanelSeparator {
            visible: root.mainView && pods.hasEarbuds && root.ncSectionVisible
            foreground: root.foreground
          }

          Column {
            visible: root.mainView && pods.hasEarbuds && root.ncSectionVisible
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
            visible: root.mainView && pods.hasEarbuds && root.transparencySectionVisible
            foreground: root.foreground
          }

          Column {
            visible: root.mainView && pods.hasEarbuds && root.transparencySectionVisible
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "TRANSPARENCY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              id: transparencyRow
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: Model.TRANSPARENCY_MODES
                Button {
                  required property var modelData
                  property string rowName: "transparency:" + modelData
                  width: (transparencyRow.width - transparencyRow.spacing * (Model.TRANSPARENCY_MODES.length - 1)) / Model.TRANSPARENCY_MODES.length
                  text: Model.transparencyModeLabel(modelData)
                  fontSize: Style.font.bodySmall
                  horizontalPadding: Style.space(2)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  active: pods.transparencyMode === modelData
                  hasCursor: root.rowHasCursor(rowName)
                  onClicked: pods.setTransparencyMode(modelData)
                  onHovered: function (h) { if (h) root.focusRow(rowName) }
                }
              }
            }
          }

          PanelSeparator {
            visible: root.mainView && pods.hasEarbuds && root.hasSoundEffects
            foreground: root.foreground
          }

          NavigationRow {
            visible: root.mainView && pods.hasEarbuds && root.hasSoundEffects
            width: parent.width
            rowName: "effects"
            title: "Sound Effects"
            subtitle: root.effectsSummary
            onActivated: root.showEffects(true)
          }

          Column {
            visible: (root.effectsView || root.dualView || root.settingsView || root.buttonsView) && pods.hasEarbuds
            width: parent.width
            spacing: Style.space(12)

            CursorSurface {
              property string rowName: "back"
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
                  text: root.buttonsView && root.selectedGesture !== "" ? "Back to button controls"
                    : root.settingsView && (root.settingsDetail === "power" || root.settingsDetail === "volume") ? "Back to preferences"
                    : root.buttonsView || root.dualView || (root.settingsView && root.settingsDetail !== "") ? "Back to Advanced Settings" : "Back to earbuds"
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
                onClicked: root.goBack()
              }
            }

            Column {
              visible: root.settingsView && root.settingsDetail === ""
              width: parent.width
              spacing: Style.space(4)
              PanelSectionHeader { text: "ADVANCED SETTINGS"; foreground: root.foreground; fontFamily: root.fontFamily }
              NavigationRow {
                visible: pods.ldacSupported || pods.hostCodec !== ""
                width: parent.width
                rowName: "detail:audio"
                title: "Audio Quality"
                subtitle: "LDAC and computer playback codec"
                onActivated: root.showDetail("audio")
              }
              NavigationRow {
                visible: pods.dualConnectionsSupported
                width: parent.width
                rowName: "dual"
                title: "Connections"
                subtitle: "Dual connections and paired devices"
                onActivated: root.showDual(true)
              }
              NavigationRow {
                visible: pods.hasButtonControls
                width: parent.width
                rowName: "buttons"
                title: "Earbud Controls"
                subtitle: "Customize left and right presses"
                onActivated: root.showButtons(true)
              }
              NavigationRow {
                visible: pods.autoPowerOffSupported || pods.touchToneSupported || pods.lowBatteryPromptSupported || pods.limitHighVolumeSupported
                width: parent.width
                rowName: "detail:preferences"
                title: "Preferences"
                subtitle: "Power, tones and volume limit"
                onActivated: root.showDetail("preferences")
              }
              NavigationRow {
                visible: pods.eqTransferSupported
                width: parent.width
                rowName: "detail:transfer"
                title: "Preset Management"
                subtitle: "Import or export saved EQ presets"
                onActivated: root.showDetail("transfer")
              }
              NavigationRow {
                visible: root.deviceInfoRows.length > 0
                width: parent.width
                rowName: "detail:info"
                title: "Device Information"
                subtitle: "Firmware, serial number and status"
                onActivated: root.showDetail("info")
              }
            }

          Column {
            visible: root.settingsView && root.settingsDetail === "audio"
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "AUDIO CODEC"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ToggleRow {
              width: parent.width
              rowName: "ldac"
              visible: pods.ldacSupported
              label: pods.switchingCodec ? "Switching codec…" : "LDAC on earbuds"
              on: pods.ldacEnabled
              onActivated: pods.setLdac(!pods.ldacEnabled)
            }

            Text {
              visible: pods.spatialAudio && !pods.ldacEnabled
              width: parent.width
              text: "Turning on LDAC turns off Spatial Audio."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Computer playback · " + Model.codecLabel(pods.hostCodec)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

            Column {
              visible: root.settingsView && root.settingsDetail === "power"
              width: parent.width
              spacing: Style.space(10)

              PanelSectionHeader {
                visible: pods.autoPowerOffSupported && pods.autoPowerOffOptions.length > 0
                text: "AUTO POWER-OFF"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                visible: pods.autoPowerOffSupported && pods.autoPowerOffOptions.length > 0
                width: parent.width
                text: "Choose when the earbuds turn off automatically."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: pods.autoPowerOffSupported ? pods.autoPowerOffOptions : []
                OptionRow {
                  required property var modelData
                  width: parent.width
                  rowName: "power:" + modelData.value
                  label: modelData.label
                  selected: pods.autoPowerOff === modelData.value
                  onActivated: pods.setAutoPowerOff(modelData.value)
                }
              }

            }

            Column {
              visible: root.settingsView && root.settingsDetail === "preferences"
              width: parent.width
              spacing: Style.space(10)
              NavigationRow {
                visible: pods.autoPowerOffSupported && pods.autoPowerOffOptions.length > 0
                width: parent.width
                rowName: "detail:power"
                title: "Auto Power-Off"
                subtitle: Model.optionLabel(pods.autoPowerOffOptions, pods.autoPowerOff)
                onActivated: root.showDetail("power")
              }
              PanelSectionHeader {
                visible: pods.touchToneSupported || pods.lowBatteryPromptSupported
                text: "PREFERENCES"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              ToggleRow {
                visible: pods.touchToneSupported
                width: parent.width
                rowName: "touchtone"
                label: "Touch tones"
                fullRow: true
                on: pods.touchTone
                onActivated: pods.setTouchTone(!pods.touchTone)
              }

              ToggleRow {
                visible: pods.lowBatteryPromptSupported
                width: parent.width
                rowName: "lowprompt"
                label: "Low-battery prompt"
                fullRow: true
                on: pods.lowBatteryPrompt
                onActivated: pods.setLowBatteryPrompt(!pods.lowBatteryPrompt)
              }

              PanelSeparator {
                visible: pods.limitHighVolumeSupported && pods.autoPowerOffSupported && pods.autoPowerOffOptions.length > 0
                foreground: root.foreground
              }

              NavigationRow {
                visible: pods.limitHighVolumeSupported
                width: parent.width
                rowName: "volumesettings"
                title: "High-Volume Limit"
                subtitle: pods.limitHighVolume ? "On · " + pods.limitDb + " dB" : "Off"
                onActivated: root.showHighVolume()
              }

            }

            Column {
              visible: root.settingsView && root.settingsDetail === "info"
              width: parent.width
              spacing: Style.space(10)
              PanelSectionHeader {
                text: "DEVICE INFORMATION"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Repeater {
                model: root.deviceInfoRows
                Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(2)
                  Text { text: modelData.label; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                  Text { width: parent.width; text: modelData.value; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WrapAnywhere }
                }
              }
            }

            Column {
              visible: root.settingsView && root.settingsDetail === "volume" && pods.limitHighVolumeSupported
              width: parent.width
              spacing: Style.space(10)

              PanelSectionHeader {
                text: "HIGH-VOLUME LIMIT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              ToggleRow {
                width: parent.width
                rowName: "volumetoggle"
                label: "Limit volume"
                fullRow: true
                on: pods.limitHighVolume
                onActivated: pods.setHighVolumeLimit(!pods.limitHighVolume)
              }

              PanelSectionHeader {
                visible: pods.limitDbOptions.length > 0
                text: "THRESHOLD"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: pods.limitDbOptions
                OptionRow {
                  required property var modelData
                  width: parent.width
                  rowName: "volumedb:" + modelData.value
                  label: modelData.label
                  selected: pods.limitDb === modelData.value
                  onActivated: pods.setLimitDb(modelData.value)
                }
              }

              PanelSectionHeader {
                visible: pods.limitRateOptions.length > 0
                text: "REFRESH RATE"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: pods.limitRateOptions
                OptionRow {
                  required property var modelData
                  width: parent.width
                  rowName: "volumerate:" + modelData.value
                  label: modelData.label
                  selected: pods.limitRate === modelData.value
                  onActivated: pods.setLimitRate(modelData.value)
                }
              }
            }

            Column {
              visible: root.buttonsView && root.selectedGesture === "" && pods.hasButtonControls
              width: parent.width
              spacing: Style.space(12)

              PanelSectionHeader {
                text: "BUTTON CONTROLS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: ["Left", "Right"]
                Column {
                  id: sideGroup
                  required property string modelData
                  width: parent.width
                  spacing: Style.space(7)

                  PanelSectionHeader {
                    text: sideGroup.modelData.toUpperCase() + " EARBUD"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Repeater {
                    model: Model.BUTTON_GESTURES.filter(function (gesture) {
                      return gesture.side === sideGroup.modelData && (pods.buttonOptions[gesture.id] || []).length > 0
                    })
                    NavigationRow {
                      required property var modelData
                      width: parent.width
                      rowName: "button:" + modelData.id
                      title: modelData.label
                      subtitle: Model.optionLabel(pods.buttonOptions[modelData.id] || [], pods.buttonBindings[modelData.id] || "")
                      onActivated: root.showGesture(modelData.id)
                    }
                  }
                }
              }

              NavigationRow {
                visible: pods.buttonResetSupported
                width: parent.width
                rowName: "resetbuttons"
                title: root.resetButtonsArmed ? "Confirm reset" : "Reset to defaults"
                subtitle: root.resetButtonsArmed ? "Replace every custom button action" : "Restore the earbuds' original controls"
                onActivated: root.confirmResetButtons()
              }
            }

            Column {
              visible: root.buttonsView && root.selectedGesture !== ""
              width: parent.width
              spacing: Style.space(10)

              PanelSectionHeader {
                text: (root.selectedGestureInfo.side + " " + root.selectedGestureInfo.label).toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: pods.buttonOptions[root.selectedGesture] || []
                OptionRow {
                  required property var modelData
                  width: parent.width
                  rowName: "buttonoption:" + modelData.value
                  label: modelData.label
                  selected: (pods.buttonBindings[root.selectedGesture] || "") === modelData.value
                  onActivated: pods.setButtonBinding(root.selectedGesture, modelData.value)
                }
              }
            }

            PanelSectionHeader {
              visible: root.effectsView
              width: parent.width
              text: "SOUND EFFECTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ToggleRow {
              visible: root.dualView && pods.dualConnectionsSupported
              width: parent.width
              rowName: "dualtoggle"
              label: "Dual Connections"
              fullRow: true
              on: pods.dualConnections
              onActivated: pods.setDualConnections(!pods.dualConnections)
            }

            PanelSeparator {
              visible: root.dualView && pods.dualConnections
              foreground: root.foreground
            }

            Column {
              visible: root.dualView && pods.dualConnections
              width: parent.width
              spacing: Style.space(8)
              PanelSectionHeader {
                text: "CURRENT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Repeater {
                model: root.currentDevices
                ConnectionRow {
                  required property var modelData
                  width: parent.width
                  rowName: "currentdevice:" + modelData.value
                  label: modelData.label
                  checked: true
                  onActivated: pods.setDeviceConnection(modelData.value, false)
                }
              }
              Text {
                visible: root.currentDevices.length === 0
                width: parent.width
                text: "No connected devices reported"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            PanelSeparator {
              visible: root.dualView && pods.dualConnections
              foreground: root.foreground
            }

            Column {
              visible: root.dualView && pods.dualConnections
              width: parent.width
              spacing: Style.space(8)
              RowLayout {
                width: parent.width
                PanelSectionHeader {
                  Layout.fillWidth: true
                  text: "HISTORY"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                Button {
                  visible: root.historyDevices.length > 0
                  text: root.manageHistory ? "Done" : "Manage"
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.rowHasCursor("dualmanage")
                  onHovered: function (h) { if (h) root.focusRow("dualmanage") }
                  onClicked: root.manageHistory = !root.manageHistory
                }
              }
              Repeater {
                model: root.historyDevices
                ConnectionRow {
                  required property var modelData
                  width: parent.width
                  rowName: (root.manageHistory ? "forgetdevice:" : "historydevice:") + modelData.value
                  label: modelData.label
                  checked: false
                  removable: root.manageHistory
                  onActivated: pods.setDeviceConnection(modelData.value, true)
                  onForgetRequested: pods.removeDualConnectionsDevice(modelData.value)
                }
              }
              Text {
                visible: root.historyDevices.length === 0
                width: parent.width
                text: "No saved devices"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Column {
              visible: root.effectsView
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
                selected: !pods.spatialAudio && !pods.customEqActive
                onActivated: root.selectDefault()
              }
              OptionRow {
                visible: pods.customEqSupported
                width: parent.width
                rowName: "custom"
                label: "Custom EQ"
                selected: pods.customEqActive
                onActivated: pods.setCustomEqBands(pods.eqBands)
              }
            }

            PanelSeparator { visible: root.effectsView; foreground: root.foreground }

            Column {
              visible: root.effectsView && !pods.spatialAudio && !pods.customEqActive && pods.eqOptions.length > 0
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

            CustomEqEditor {
              id: customEditor
              visible: root.effectsView && pods.customEqActive
              width: parent.width
              service: pods
              foreground: root.foreground
              fontFamily: root.fontFamily
              cursorRow: root.cursorActive ? root.cursorRow : ""
              onFocusRowRequested: function (name) { root.focusRow(name) }
              onReleaseFocus: keyCatcher.forceActiveFocus()
              onRevealItem: function (item) {
                if (!item || !root.effectsView || !visible) return
                var y = item.mapToItem(column, 0, 0).y
                if (y < panelFlick.contentY) panelFlick.contentY = y
                else if (y + item.height > panelFlick.contentY + panelFlick.height)
                  panelFlick.contentY = Math.max(0, y + item.height - panelFlick.height)
              }
            }

            Column {
              visible: root.settingsView && root.settingsDetail === "transfer" && pods.eqTransferSupported
              width: parent.width
              spacing: Style.space(8)
              PanelSectionHeader {
                text: "PRESET TRANSFER"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }
              Button {
                visible: pods.customEqOptions.length > 0
                text: "Copy saved presets"
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.rowHasCursor("eqexport")
                enabled: !pods.busy
                onClicked: pods.transferEq("export")
                onHovered: function (h) { if (h) root.focusRow("eqexport") }
              }
              Button {
                text: root.importEqArmed ? "Confirm import from clipboard" : "Import from clipboard"
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.rowHasCursor("eqimport")
                enabled: !pods.busy
                onClicked: root.importEq()
                onHovered: function (h) { if (h) root.focusRow("eqimport") }
              }
              Text {
                visible: root.importEqArmed
                width: parent.width
                text: "Importing replaces saved presets with matching names. Click again to confirm."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Column {
              visible: root.effectsView && pods.spatialAudio && pods.spatialAudioModeSupported
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

  component ConnectionRow: CursorSurface {
    id: connectionRow
    property string rowName: ""
    property string label: ""
    property bool checked: false
    property bool removable: false
    signal activated()
    signal forgetRequested()
    foreground: root.foreground
    hasCursor: root.rowHasCursor(rowName)
    implicitHeight: Math.max(connectionLabel.implicitHeight, Style.space(28)) + Style.space(14)
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: !connectionRow.removable && pods.individualConnectionsSupported ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: root.focusRow(connectionRow.rowName)
      onClicked: if (!connectionRow.removable && pods.individualConnectionsSupported) connectionRow.activated()
    }
    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)
      Text {
        id: connectionLabel
        Layout.fillWidth: true
        text: connectionRow.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      ToggleSwitch {
        visible: !connectionRow.removable && pods.individualConnectionsSupported
        Layout.alignment: Qt.AlignVCenter
        trackHeight: Math.round(connectionLabel.font.pixelSize * 1.2)
        checked: connectionRow.checked
        interactive: false
        foreground: root.foreground
        opacity: pods.updating || pods.statusStale ? 0.5 : 1
        MouseArea {
          anchors.fill: parent
          enabled: !pods.updating && !pods.statusStale
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.focusRow(connectionRow.rowName)
          onClicked: connectionRow.activated()
        }
      }
      Text {
        visible: !connectionRow.removable && !pods.individualConnectionsSupported
        text: connectionRow.checked ? "Connected" : "Saved"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      PanelActionButton {
        visible: connectionRow.removable
        enabled: !pods.updating && !pods.statusStale
        Layout.alignment: Qt.AlignVCenter
        iconText: "󰅙"
        tooltipText: "Forget device"
        foreground: root.foreground
        hoverColor: root.foreground
        fontFamily: root.fontFamily
        hasCursor: root.rowHasCursor(connectionRow.rowName)
        onHovered: function (h) { if (h) root.focusRow(connectionRow.rowName) }
        onClicked: connectionRow.forgetRequested()
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
          visible: nav.subtitle !== ""
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

  component BatteryCell: RowLayout {
    id: batteryCell
    property string label: ""
    property int level: Model.LEVEL_UNKNOWN
    property bool charging: false
    readonly property color levelColor: level >= 0 && level <= pods.lowBatteryPercent && !charging ? root.urgent : root.soundAccent
    spacing: Style.space(8)
    Accessible.role: Accessible.StaticText
    Accessible.name: label + " battery: " + (level < 0 ? "unknown" : level + " percent") + (charging ? ", charging" : "")
    ControlIcon {
      kind: batteryCell.label.toLowerCase()
      ink: root.foreground
      Layout.preferredWidth: Style.space(17)
      Layout.preferredHeight: Style.space(17)
      Layout.alignment: Qt.AlignVCenter
    }
    Text {
      Layout.preferredWidth: Style.space(40)
      text: batteryCell.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(4)
      Layout.alignment: Qt.AlignVCenter
      radius: height / 2
      color: Qt.alpha(root.foreground, 0.15)
      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, batteryCell.level / 100))
        height: parent.height
        radius: height / 2
        color: batteryCell.levelColor
      }
    }
    Text {
      Layout.preferredWidth: Style.space(12)
      text: batteryCell.charging ? "ϟ" : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      Layout.preferredWidth: Style.space(38)
      horizontalAlignment: Text.AlignRight
      text: batteryCell.level < 0 ? "—" : batteryCell.level + "%"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

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
    property bool fullRow: false
    signal activated()

    // Unlike the checkmark-list rows, only the switch itself is
    // clickable/hoverable — the row surface never paints a cursor fill/border
    // of its own, so hovering the label doesn't light up the whole row. The
    // switch shows its own compact cursor ring instead (below).
    foreground: root.foreground
    hasCursor: fullRow && root.rowHasCursor(rowName)
    implicitHeight: Math.max(toggleLabel.implicitHeight, toggleSwitch.implicitHeight) + (fullRow ? Style.space(16) : 0)

    MouseArea {
      anchors.fill: parent
      enabled: toggleRow.fullRow
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(toggleRow.rowName)
      onClicked: toggleRow.activated()
    }

    // Flush with the Mode row above — no row background to pad out to here.
    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: toggleRow.fullRow ? Style.space(10) : 0
      anchors.rightMargin: toggleRow.fullRow ? Style.space(10) : 0
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
        hasCursor: !toggleRow.fullRow && root.rowHasCursor(toggleRow.rowName)
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
