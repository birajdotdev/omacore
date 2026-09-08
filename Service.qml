import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool connected: false
  property string ancMode: ""
  property int leftLevel: Model.LEVEL_UNKNOWN
  property int rightLevel: Model.LEVEL_UNKNOWN
  property int caseLevel: Model.LEVEL_UNKNOWN
  property bool leftCharging: false
  property bool rightCharging: false
  property bool windNoiseSuppressionSupported: false
  property bool windNoiseSuppression: false

  property bool transparencyModeSupported: false
  property string transparencyMode: ""
  property bool noiseCancelingModeSupported: false
  property string noiseCancelingMode: ""
  property bool manualNoiseCancelingSupported: false
  property int manualNoiseCancelingLevel: Model.LEVEL_UNKNOWN
  property bool multiSceneNoiseCancelingSupported: false
  property string multiSceneNoiseCanceling: ""
  property bool realTimeAdaptiveNoiseCancelingSupported: false
  property bool realTimeAdaptiveNoiseCanceling: false
  property bool spatialAudioSupported: false
  property bool spatialAudio: false
  property bool spatialAudioModeSupported: false
  property string spatialAudioMode: ""
  readonly property string soundEffect: spatialAudio ? spatialAudioMode : Model.SOUND_EFFECT_OFF

  property string lastError: ""
  property string actionStatus: ""

  // True when omacore-status couldn't find the OpenSCQ30 CLI on PATH. The
  // panel then offers an in-widget install button instead of hiding silently.
  property bool cliMissing: false

  // Populated by the discovery script — the friendly Bluetooth device name
  // (e.g. "Soundcore R60i NC"), used for the panel hero title.
  property string deviceName: "Soundcore"
  property string deviceModel: ""
  // The MAC address discovered by omacore-status, used for set commands.
  property string discoveredMac: ""

  readonly property int pollIntervalSec: intSetting("pollIntervalSec", 30, 10, 300)
  readonly property bool busy: statusProcess.running || actionProcess.running
  readonly property bool hasEarbuds: connected

  readonly property int lowBatteryPercent: 20
  readonly property bool notifyEnabled: setting("notifyEnabled", true) === true

  property bool leftLowNotified: false
  property bool rightLowNotified: false
  property bool caseLowNotified: false
  property var _notifyQueue: []

  property string _pendingMode: ""
  property bool _windNoisePending: false
  property bool _pendingWindNoiseValue: false

  property var _pendingWrites: ({})
  readonly property int settleHoldMs: 4000
  readonly property int actionStatusMs: 2200

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.birajdotdev.omacore"
  readonly property string statusScript: pluginDir + "/omacore-status"
  readonly property string setScript: pluginDir + "/omacore-set"
  readonly property string installScript: pluginDir + "/omacore-install"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function modeLabel(mode) {
    return Model.modeLabel(mode)
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [statusScript]
    statusProcess.running = true
    pollWatchdog.restart()
  }

  // Opens the bundled omacore-install in a visible terminal so the user can
  // watch the download; no sudo needed (installs into ~/.local). The regular
  // poll picks the CLI up once it lands on PATH, so no manual refresh needed.
  function installCli() {
    if (installProcess.running) return
    installProcess.command = ["omarchy-launch-terminal", installScript]
    installProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.connected) {
      var missing = parsed.cliMissing === true
      if (missing !== cliMissing) cliMissing = missing
      if (connected) _noteDisconnected("No paired Soundcore device is connected.")
      else if (missing) lastError = "openscq30 / openscq30-cli not found on PATH."
      return
    }

    cliMissing = false

    discoveredMac = parsed.mac || ""
    deviceName = parsed.name || "Soundcore"
    deviceModel = parsed.model || ""

    var status = Model.statusFromMap(parsed.values || {})
    if (!status.ok) {
      _noteDisconnected("Could not read the earbuds' status.")
      return
    }

    connected = true
    lastError = ""
    leftLevel = status.leftLevel
    rightLevel = status.rightLevel
    caseLevel = status.caseLevel
    leftCharging = status.leftCharging
    rightCharging = status.rightCharging
    ancMode = _settle(status.ancMode)
    windNoiseSuppressionSupported = status.windNoiseSuppressionSupported
    windNoiseSuppression = status.windNoiseSuppressionSupported
      ? _settleWindNoise(status.windNoiseSuppression)
      : false

    transparencyModeSupported = status.transparencyModeSupported
    transparencyMode = status.transparencyModeSupported
      ? _settleValue("transparencyMode", status.transparencyMode) : ""
    noiseCancelingModeSupported = status.noiseCancelingModeSupported
    noiseCancelingMode = status.noiseCancelingModeSupported
      ? _settleValue("noiseCancelingMode", status.noiseCancelingMode) : ""
    manualNoiseCancelingSupported = status.manualNoiseCancelingSupported
    manualNoiseCancelingLevel = status.manualNoiseCancelingSupported
      ? _settleValue("manualNoiseCancelingLevel", status.manualNoiseCancelingLevel) : Model.LEVEL_UNKNOWN
    multiSceneNoiseCancelingSupported = status.multiSceneNoiseCancelingSupported
    multiSceneNoiseCanceling = status.multiSceneNoiseCancelingSupported
      ? _settleValue("multiSceneNoiseCanceling", status.multiSceneNoiseCanceling) : ""
    realTimeAdaptiveNoiseCancelingSupported = status.realTimeAdaptiveNoiseCancelingSupported
    realTimeAdaptiveNoiseCanceling = status.realTimeAdaptiveNoiseCancelingSupported
      ? _settleValue("realTimeAdaptiveNoiseCanceling", status.realTimeAdaptiveNoiseCanceling) : false
    spatialAudioSupported = status.spatialAudioSupported
    spatialAudio = status.spatialAudioSupported
      ? _settleValue("spatialAudio", status.spatialAudio) : false
    spatialAudioModeSupported = status.spatialAudioModeSupported
    spatialAudioMode = status.spatialAudioModeSupported
      ? _settleValue("spatialAudioMode", status.spatialAudioMode) : ""

    _checkLowBattery("leftLowNotified", "Left earbud", leftLevel, leftCharging)
    _checkLowBattery("rightLowNotified", "Right earbud", rightLevel, rightCharging)
    _checkLowBattery("caseLowNotified", "Case", caseLevel, false)
  }

  function _noteDisconnected(message) {
    if (connected) _notify("Soundcore earbuds disconnected", message, "normal")
    connected = false
    lastError = message
    discoveredMac = ""
    leftLowNotified = false
    rightLowNotified = false
    caseLowNotified = false
  }

  function _checkLowBattery(flagName, label, level, charging) {
    var low = level !== Model.LEVEL_UNKNOWN && level <= lowBatteryPercent && !charging
    if (!low) {
      root[flagName] = false
      return
    }
    if (root[flagName]) return
    root[flagName] = true
    _notify(label + " battery low", level + "% remaining", "normal")
  }

  function _notify(headline, description, urgency) {
    if (!notifyEnabled) return
    _notifyQueue.push({ headline: headline, description: description, urgency: urgency })
    _pumpNotifyQueue()
  }

  function _pumpNotifyQueue() {
    if (notifyProcess.running || _notifyQueue.length === 0) return
    var next = _notifyQueue.shift()
    notifyProcess.command = ["omarchy-notification-send", "--app-name", "Soundcore", "-u", next.urgency, next.headline, next.description]
    notifyProcess.running = true
  }

  function _settle(reported) {
    if (_pendingMode === "") return reported
    if (reported === _pendingMode) {
      _pendingMode = ""
      settleTimer.stop()
      return reported
    }
    return _pendingMode
  }

  function setAncMode(mode) {
    if (mode === "" || !connected || discoveredMac === "" || actionProcess.running) return
    _pendingMode = mode
    ancMode = mode
    settleTimer.restart()
    actionProcess.command = [setScript, discoveredMac, Model.SETTING_AMBIENT_SOUND_MODE + "=" + mode]
    actionProcess.running = true
  }

  function _settleWindNoise(reported) {
    if (!_windNoisePending) return reported
    if (reported === _pendingWindNoiseValue) {
      _windNoisePending = false
      windNoiseSettleTimer.stop()
      return reported
    }
    return _pendingWindNoiseValue
  }

  function setWindNoiseSuppression(enabled) {
    if (!connected || !windNoiseSuppressionSupported || discoveredMac === "" || actionProcess.running) return
    _windNoisePending = true
    _pendingWindNoiseValue = enabled
    windNoiseSuppression = enabled
    windNoiseSettleTimer.restart()
    actionProcess.command = [setScript, discoveredMac, Model.SETTING_WIND_NOISE_SUPPRESSION + "=" + (enabled ? "true" : "false")]
    actionProcess.running = true
  }

  function _settleValue(propName, reported) {
    if (!(propName in _pendingWrites)) return reported
    if (reported === _pendingWrites[propName]) {
      delete _pendingWrites[propName]
      if (Object.keys(_pendingWrites).length === 0) pendingSettleTimer.stop()
      return reported
    }
    return _pendingWrites[propName]
  }

  function _beginWrite(propName, value) {
    _pendingWrites[propName] = value
    root[propName] = value
    pendingSettleTimer.restart()
  }

  function setNoiseCancelingMode(mode) {
    if (mode === "" || !connected || !noiseCancelingModeSupported || discoveredMac === "" || actionProcess.running) return
    _beginWrite("noiseCancelingMode", mode)
    actionProcess.command = [setScript, discoveredMac, Model.SETTING_NOISE_CANCELING_MODE + "=" + mode]
    actionProcess.running = true
  }

  function setManualNoiseCancelingLevel(level) {
    if (!connected || !manualNoiseCancelingSupported || discoveredMac === "" || actionProcess.running) return
    var clamped = Math.max(Model.MANUAL_LEVEL_MIN, Math.min(Model.MANUAL_LEVEL_MAX, Math.round(level)))
    _beginWrite("manualNoiseCancelingLevel", clamped)
    actionProcess.command = [setScript, discoveredMac, Model.SETTING_MANUAL_NOISE_CANCELING + "=" + clamped]
    actionProcess.running = true
  }

  function setMultiSceneNoiseCanceling(scene) {
    if (scene === "" || !connected || !multiSceneNoiseCancelingSupported || discoveredMac === "" || actionProcess.running) return
    _beginWrite("multiSceneNoiseCanceling", scene)
    actionProcess.command = [setScript, discoveredMac, Model.SETTING_MULTI_SCENE_NOISE_CANCELING + "=" + scene]
    actionProcess.running = true
  }

  function setRealTimeAdaptiveNoiseCanceling(enabled) {
    if (!connected || !realTimeAdaptiveNoiseCancelingSupported || discoveredMac === "" || actionProcess.running) return
    _beginWrite("realTimeAdaptiveNoiseCanceling", enabled)
    actionProcess.command = [setScript, discoveredMac, Model.SETTING_REALTIME_ADAPTIVE_NOISE_CANCELING + "=" + (enabled ? "true" : "false")]
    actionProcess.running = true
  }

  function setTransparencyMode(mode) {
    if (mode === "" || !connected || !transparencyModeSupported || discoveredMac === "" || actionProcess.running) return
    _beginWrite("transparencyMode", mode)
    actionProcess.command = [setScript, discoveredMac, Model.SETTING_TRANSPARENCY_MODE + "=" + mode]
    actionProcess.running = true
  }

  function setSoundEffect(effect) {
    if (effect === "" || !connected || !spatialAudioSupported || !spatialAudioModeSupported || discoveredMac === "" || actionProcess.running) return
    _beginWrite("spatialAudio", true)
    _beginWrite("spatialAudioMode", effect)
    actionProcess.command = [setScript, discoveredMac,
      Model.SETTING_SPATIAL_AUDIO + "=true",
      Model.SETTING_SPATIAL_AUDIO_MODE + "=" + effect]
    actionProcess.running = true
  }

  Timer {
    id: pollTimer
    interval: root.pollIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: if (statusProcess.running) statusProcess.running = false
  }

  Timer {
    id: settleTimer
    interval: root.settleHoldMs
    repeat: false
    onTriggered: { root._pendingMode = ""; root.refresh() }
  }

  Timer {
    id: windNoiseSettleTimer
    interval: root.settleHoldMs
    repeat: false
    onTriggered: { root._windNoisePending = false; root.refresh() }
  }

  Timer {
    id: pendingSettleTimer
    interval: root.settleHoldMs
    repeat: false
    onTriggered: { root._pendingWrites = {}; root.refresh() }
  }

  Timer {
    id: actionStatusTimer
    interval: root.actionStatusMs
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else root._noteDisconnected(Model.elideError(statusErr.text) || "Could not reach the earbuds.")
    }
  }

  Process {
    id: notifyProcess
    running: false
    command: []
    onExited: root._pumpNotifyQueue()
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root._pendingMode = ""
        settleTimer.stop()
        root._windNoisePending = false
        windNoiseSettleTimer.stop()
        root._pendingWrites = {}
        pendingSettleTimer.stop()
        root.actionStatus = Model.elideError(actionErr.text) || "openscq30 rejected the command"
        actionStatusTimer.restart()
      }
      root.refresh()
    }
  }

  Process {
    id: installProcess
    running: false
    command: []
    onExited: root.refresh()
  }
}
