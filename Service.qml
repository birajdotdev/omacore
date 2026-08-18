import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  // Whether the `which`/`test -x` probe has found the CLI at all. Checked once
  // and cached, same as the Tailscale panel: re-probing on every poll would
  // just be extra process spawns for a binary that is not going to move.
  property bool installed: false
  property bool checkedInstalled: false
  // True once a `device ... setting -g ...` call has actually gotten a reply,
  // meaning the earbuds are paired, in range and connected.
  property bool connected: false
  property string ancMode: ""
  property int leftLevel: Model.LEVEL_UNKNOWN
  property int rightLevel: Model.LEVEL_UNKNOWN
  property int caseLevel: Model.LEVEL_UNKNOWN
  property bool leftCharging: false
  property bool rightCharging: false
  // False on models/firmware where openscq30 doesn't report this setting at all;
  // the panel hides the row rather than showing a toggle that will always fail.
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
  // Sound Effects as the panel shows it: "Off" when spatial audio is disabled,
  // otherwise whichever mode (Music/Movie/Gaming) spatialAudioMode holds.
  readonly property string soundEffect: spatialAudio ? spatialAudioMode : Model.SOUND_EFFECT_OFF

  property string lastError: ""
  property string actionStatus: ""

  readonly property string macAddress: String(setting("macAddress", "") || "").trim()
  readonly property string model: String(setting("model", "SoundcoreD1202C") || "").trim()
  readonly property int pollIntervalSec: intSetting("pollIntervalSec", 30, 10, 300)
  readonly property string ctlPath: String(setting("ctlPath", "") || "").trim()
  readonly property string resolvedBin: ctlPath !== "" ? ctlPath : "openscq30"
  readonly property bool busy: statusProcess.running || actionProcess.running
  readonly property bool hasEarbuds: connected

  readonly property int lowBatteryPercent: 20
  readonly property bool notifyEnabled: setting("notifyEnabled", true) === true

  // Latched so a bud sitting at e.g. 15% only notifies once, not every poll.
  // Cleared on disconnect so a fresh drop after reconnecting notifies again.
  property bool leftLowNotified: false
  property bool rightLowNotified: false
  property bool caseLowNotified: false
  property var _notifyQueue: []

  // Held over an incoming poll until the CLI agrees, so a write already in
  // flight when the click landed cannot snap the control back.
  property string _pendingMode: ""
  // Same optimistic-update pattern as _pendingMode, for the wind noise toggle.
  // A plain bool can't double as "no pending change" the way "" does for mode,
  // hence the separate has-pending flag.
  property bool _windNoisePending: false
  property bool _pendingWindNoiseValue: false

  // Generic version of the _pendingMode/_windNoisePending pattern above, for the
  // rest of the writable settings this widget added afterward: one shared map of
  // "property name" -> "value we expect the next poll to report" and one shared
  // settle timer, instead of a bespoke pending-flag/timer pair per setting.
  property var _pendingWrites: ({})
  readonly property int settleHoldMs: 4000
  readonly property int actionStatusMs: 2200

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
    if (macAddress === "") {
      connected = false
      lastError = "Set the earbuds' Bluetooth MAC address in this widget's settings."
      return
    }
    if (!checkedInstalled) {
      whichProcess.command = resolvedBin.indexOf("/") >= 0
        ? ["test", "-x", resolvedBin]
        : ["which", resolvedBin]
      whichProcess.running = true
      return
    }
    if (!installed) {
      connected = false
      lastError = "openscq30 CLI not found. Install openscq30-cli(-bin) from the AUR."
      return
    }
    if (statusProcess.running) return
    statusProcess.command = [resolvedBin, "device", "-a", macAddress, "setting"]
      .concat(Model.POLL_SETTING_IDS.reduce(function (args, id) { return args.concat(["-g", id]) }, []))
      .concat(["--json"])
    statusProcess.running = true
    pollWatchdog.restart()
  }

  function applyStatus(raw) {
    var parsed = Model.parseSettingsJson(raw)
    if (!parsed.ok) {
      _noteDisconnected("Could not read the earbuds' status.")
      return
    }
    connected = true
    lastError = ""
    var status = Model.statusFromMap(parsed.map)
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

  // Fires once on the connected -> disconnected edge, not on every failed poll
  // while it stays down, and not on the very first probe before we ever connected.
  function _noteDisconnected(message) {
    if (connected) _notify("Soundcore earbuds disconnected", message, "normal")
    connected = false
    lastError = message
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
    if (mode === "" || !connected || actionProcess.running) return
    _pendingMode = mode
    ancMode = mode
    settleTimer.restart()
    actionProcess.command = [resolvedBin, "device", "-a", macAddress, "setting", "-s", Model.SETTING_AMBIENT_SOUND_MODE + "=" + mode]
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

  // Toggling this while in Normal ambient sound mode requires briefly switching to
  // Noise Canceling and back; openscq30 handles that multi-step packet exchange
  // itself, so this is a plain setting write same as setAncMode.
  function setWindNoiseSuppression(enabled) {
    if (!connected || !windNoiseSuppressionSupported || actionProcess.running) return
    _windNoisePending = true
    _pendingWindNoiseValue = enabled
    windNoiseSuppression = enabled
    windNoiseSettleTimer.restart()
    actionProcess.command = [resolvedBin, "device", "-a", macAddress, "setting", "-s", Model.SETTING_WIND_NOISE_SUPPRESSION + "=" + (enabled ? "true" : "false")]
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
    if (mode === "" || !connected || !noiseCancelingModeSupported || actionProcess.running) return
    _beginWrite("noiseCancelingMode", mode)
    actionProcess.command = [resolvedBin, "device", "-a", macAddress, "setting", "-s", Model.SETTING_NOISE_CANCELING_MODE + "=" + mode]
    actionProcess.running = true
  }

  function setManualNoiseCancelingLevel(level) {
    if (!connected || !manualNoiseCancelingSupported || actionProcess.running) return
    var clamped = Math.max(Model.MANUAL_LEVEL_MIN, Math.min(Model.MANUAL_LEVEL_MAX, Math.round(level)))
    _beginWrite("manualNoiseCancelingLevel", clamped)
    actionProcess.command = [resolvedBin, "device", "-a", macAddress, "setting", "-s", Model.SETTING_MANUAL_NOISE_CANCELING + "=" + clamped]
    actionProcess.running = true
  }

  function setMultiSceneNoiseCanceling(scene) {
    if (scene === "" || !connected || !multiSceneNoiseCancelingSupported || actionProcess.running) return
    _beginWrite("multiSceneNoiseCanceling", scene)
    actionProcess.command = [resolvedBin, "device", "-a", macAddress, "setting", "-s", Model.SETTING_MULTI_SCENE_NOISE_CANCELING + "=" + scene]
    actionProcess.running = true
  }

  function setRealTimeAdaptiveNoiseCanceling(enabled) {
    if (!connected || !realTimeAdaptiveNoiseCancelingSupported || actionProcess.running) return
    _beginWrite("realTimeAdaptiveNoiseCanceling", enabled)
    actionProcess.command = [resolvedBin, "device", "-a", macAddress, "setting", "-s", Model.SETTING_REALTIME_ADAPTIVE_NOISE_CANCELING + "=" + (enabled ? "true" : "false")]
    actionProcess.running = true
  }

  function setTransparencyMode(mode) {
    if (mode === "" || !connected || !transparencyModeSupported || actionProcess.running) return
    _beginWrite("transparencyMode", mode)
    actionProcess.command = [resolvedBin, "device", "-a", macAddress, "setting", "-s", Model.SETTING_TRANSPARENCY_MODE + "=" + mode]
    actionProcess.running = true
  }

  // Sets spatialAudio=true and spatialAudioMode=<effect> together in one call,
  // same as openscq30's own app does — this widget doesn't offer a way to turn
  // spatial audio off, only to pick which mode it plays in.
  function setSoundEffect(effect) {
    if (effect === "" || !connected || !spatialAudioSupported || !spatialAudioModeSupported || actionProcess.running) return
    _beginWrite("spatialAudio", true)
    _beginWrite("spatialAudioMode", effect)
    actionProcess.command = [resolvedBin, "device", "-a", macAddress, "setting",
      "-s", Model.SETTING_SPATIAL_AUDIO + "=true",
      "-s", Model.SETTING_SPATIAL_AUDIO_MODE + "=" + effect]
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
    // Every earbuds poll opens a fresh Bluetooth connection, which can hang if
    // the earbuds are out of range but BlueZ has not noticed yet. Reap it well
    // inside the refresh interval so a stuck poll does not stop refreshing.
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
    id: whichProcess
    running: false
    command: []
    onExited: function (exitCode) {
      root.checkedInstalled = true
      root.installed = exitCode === 0
      root.refresh()
    }
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
}
