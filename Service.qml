import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool liveUpdates: false
  property bool panelOpen: false
  onLiveUpdatesChanged: if (liveUpdates) refresh()

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
  property bool ldacSupported: false
  property bool ldacEnabled: false
  property bool autoPowerOffSupported: false
  property string autoPowerOff: ""
  property var autoPowerOffOptions: []
  property bool touchToneSupported: false
  property bool touchTone: false
  property bool lowBatteryPromptSupported: false
  property bool lowBatteryPrompt: false
  property var deviceInfo: ({})
  property bool limitHighVolumeSupported: false
  property bool limitHighVolume: false
  property bool limitDbSupported: false
  property int limitDb: Model.LEVEL_UNKNOWN
  property var limitDbOptions: []
  property bool limitRateSupported: false
  property string limitRate: ""
  property var limitRateOptions: []
  property var buttonBindings: ({})
  property var buttonOptions: ({})
  property bool buttonResetSupported: false
  readonly property bool hasButtonControls: Object.keys(buttonOptions).length > 0
  property string hostCodec: ""
  property string codecRequestedMac: ""
  readonly property string soundEffect: spatialAudio ? spatialAudioMode : Model.SOUND_EFFECT_OFF
  property bool dualConnectionsSupported: false
  property bool dualConnections: false
  property bool dualConnectionsDevicesSupported: false
  property var dualConnectionsDevices: []
  property var dualConnectionsOptions: []
  readonly property bool individualConnectionsSupported: deviceModel === "SoundcoreD1202" || deviceModel === "SoundcoreD1202C"

  property bool statusStale: false
  property var eqOptions: []
  property string eqPreset: ""
  property var eqSpec: null
  property var eqBands: []
  property var customEqOptions: []
  property string customEqProfile: ""
  property bool customEqProfilesSupported: false
  property bool eqTransferSupported: false
  readonly property bool customEqSupported: eqSpec !== null && eqBands.length === eqSpec.bandHz.length
  readonly property bool customEqActive: customEqSupported && !spatialAudio && eqPreset === ""
  property var _actionQueue: []
  property int queuedActions: 0
  readonly property bool updating: actionProcess.running || queuedActions > 0 || transferProcess.running
  property string lastError: ""
  property string actionStatus: ""
  readonly property bool switchingCodec: actionProcess.running && actionProcess.command[0] === ldacScript
  property bool actionStatusError: false

  // True when omacore-status couldn't find the OpenSCQ30 CLI on PATH. The
  // panel then offers an explicit install action instead of hiding silently.
  property bool cliMissing: false
  property bool dependencyNoticeShown: false

  // True when something is connected over Bluetooth but not registered with
  // OpenSCQ30 yet (its MAC has no model row in `paired-devices list`).
  property bool registeredMissing: false
  property string unregisteredMac: ""
  property string unregisteredName: ""
  // When the connected device's name uniquely identifies one supported model,
  // omacore-status sends it here so the widget can register it automatically.
  property string suggestedModel: ""
  property var registerModels: []
  property bool registering: false

  // Populated by the discovery script — the friendly Bluetooth device name
  // (e.g. "Soundcore R60i NC"), used for the panel hero title.
  property string deviceName: "Soundcore"
  property string deviceModel: ""
  property var availableDevices: []
  // The MAC address discovered by omacore-status, used for set commands.
  property string discoveredMac: ""

  readonly property int pollIntervalSec: intSetting("pollIntervalSec", 30, 10, 300)
  readonly property string deviceMatch: String(setting("deviceMatch", "")).trim()
  onDeviceMatchChanged: refresh()
  readonly property bool busy: statusProcess.running || actionProcess.running || transferProcess.running
  readonly property bool choosingDevice: deviceChoiceProcess.running
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
  readonly property int actionStatusMs: 5000

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.birajdotdev.omacore"
  readonly property string statusScript: pluginDir + "/omacore-status"
  readonly property string setScript: pluginDir + "/omacore-set"
  readonly property string codecScript: pluginDir + "/omacore-codec"
  readonly property string ldacScript: pluginDir + "/omacore-ldac"
  readonly property string eqTransferScript: pluginDir + "/omacore-eq-transfer"
  readonly property string installScript: pluginDir + "/omacore-install"
  readonly property string registerScript: pluginDir + "/omacore-register"
  readonly property string notificationIcon: pluginDir + "/soundcore-logo.svg"

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
    if (statusProcess.running || updating || deviceChoiceProcess.running) return
    statusProcess.command = deviceMatch ? [statusScript, "--device-match", deviceMatch] : [statusScript]
    statusProcess.running = true
    pollWatchdog.restart()
  }

  function refreshCodec() {
    if (!connected || discoveredMac === "" || codecProcess.running) return
    codecRequestedMac = discoveredMac
    codecProcess.command = [codecScript, discoveredMac]
    codecProcess.running = true
  }

  function chooseDevice(mac) {
    if (statusProcess.running || updating || deviceChoiceProcess.running) return
    if (mac !== "" && !availableDevices.some(function (device) { return device.mac === mac })) return
    if (mac === deviceMatch) return
    _clearWrites()
    connected = false
    discoveredMac = ""
    hostCodec = ""
    lastError = "Switching Soundcore device…"
    deviceChoiceProcess.command = ["omarchy", "bar", "set", "io.github.birajdotdev.omacore", "deviceMatch", mac]
    deviceChoiceProcess.running = true
  }

  // Opens the bundled installer in Omarchy's centered floating terminal so
  // the user can review the confirmation and watch the download.
  function installCli() {
    if (installProcess.running) return
    installProcess.command = ["omarchy-launch-floating-terminal-with-presentation", installScript]
    installProcess.running = true
  }

  function notifyDependencyMissing() {
    if (dependencyNoticeShown) return
    dependencyNoticeShown = true
    _notifyQueue.push({
      headline: "Set up Omacore for Soundcore earbuds",
      description: "OpenSCQ30 is missing. Click to review the pinned, hash-verified CLI installation. Nothing downloads until you confirm.",
      urgency: "normal",
      icon: notificationIcon,
      exec: ["omarchy-launch-floating-terminal-with-presentation", installScript]
    })
    _pumpNotifyQueue()
  }

  property bool cliInstalling: false

  // Auto-heal for registration: a connected device whose model is unambiguous
  // gets registered the moment omacore-status first reports it. If the add
  // fails (or the model was ambiguous), the panel keeps a dropdown + button so
  // the user can pick it; retries are staggered to avoid hammering on a
  // persistent failure.
  readonly property int registerRetryMs: 10 * 60 * 1000
  property var _registerFailedAt: 0

  function _startAutoRegister() {
    if (registering || registerProcess.running) return
    if (unregisteredMac === "" || suggestedModel === "") return
    if (_registerFailedAt !== 0 && Date.now() - _registerFailedAt < registerRetryMs) return
    _registerFailedAt = 0
    registering = true
    _notify("Registering " + unregisteredName, "OpenSCQ30 needs a model for this device — auto-detected " + suggestedModel + " and registering it now.", "normal")
    registerProcess.command = [registerScript, "--mac", unregisteredMac, "--model", suggestedModel, "--silent"]
    registerProcess.running = true
  }

  // Manual path: the panel's dropdown picks a model (used when the device name
  // doesn't uniquely identify one, or after an auto-register failed).
  function registerDevice(model) {
    if (registering || registerProcess.running || unregisteredMac === "" || !model) return
    registering = true
    registerProcess.command = [registerScript, "--mac", unregisteredMac, "--model", model, "--silent"]
    registerProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (parsed.readError || typeof parsed.connected !== "boolean") {
      _noteReadError(parsed.error || "Invalid status response.")
      return
    }
    statusStale = false
    availableDevices = Array.isArray(parsed.devices) ? parsed.devices : []
    if (!parsed.connected) {
      var missing = parsed.cliMissing === true
      if (missing && !cliMissing) notifyDependencyMissing()
      if (missing !== cliMissing) cliMissing = missing
      var needReg = parsed.registeredMissing === true
      if (needReg !== registeredMissing) registeredMissing = needReg
      if (connected) _noteDisconnected("No paired Soundcore device is connected.")
      else if (missing) {
        registeredMissing = false
        lastError = "OpenSCQ30 CLI is not installed."
      } else if (needReg) {
        unregisteredMac = parsed.unregisteredMac || ""
        unregisteredName = parsed.unregisteredName || ""
        suggestedModel = parsed.suggestedModel || ""
        registerModels = parsed.models || []
        lastError = "Connected over Bluetooth but not registered with OpenSCQ30 yet."
        _startAutoRegister()
      } else {
        registeredMissing = false
        unregisteredMac = ""
        unregisteredName = ""
        suggestedModel = ""
        registerModels = []
        lastError = parsed.preferredMissing ? "Preferred Soundcore device is not connected. Choose another below." : "No paired Soundcore device is connected."
      }
      return
    }

    cliMissing = false
    registeredMissing = false
    registering = false

    if (discoveredMac !== "" && discoveredMac !== parsed.mac) {
      _clearWrites()
      hostCodec = ""
      leftLowNotified = false
      rightLowNotified = false
      caseLowNotified = false
    }
    discoveredMac = parsed.mac || ""
    deviceName = parsed.name || "Soundcore"
    deviceModel = parsed.model || ""

    eqSpec = Model.eqSpecification(parsed.schema)
    var bands = Model.normalizeEqBands((parsed.values || {})[Model.SETTING_EQ_BANDS], eqSpec)
    eqBands = bands ? _settleValue("eqBands", bands) : []
    customEqOptions = Model.selectOptions(parsed.schema, Model.SETTING_CUSTOM_EQ)
    customEqProfilesSupported = Model.has(parsed.values || {}, Model.SETTING_CUSTOM_EQ)
    eqTransferSupported = (parsed.schema || []).some(function (category) { return category.categoryId === "equalizerImportExport" })
    customEqProfile = _settleValue("customEqProfile", String((parsed.values || {})[Model.SETTING_CUSTOM_EQ] || ""))
    eqOptions = Model.selectOptions(parsed.schema, Model.SETTING_EQ_PRESET)
    eqPreset = _settleValue("eqPreset", String((parsed.values || {})[Model.SETTING_EQ_PRESET] || ""))
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
    ldacSupported = status.ldacSupported
    ldacEnabled = status.ldacSupported
      ? _settleValue("ldacEnabled", status.ldacEnabled) : false
    autoPowerOffSupported = status.autoPowerOffSupported
    autoPowerOff = status.autoPowerOffSupported
      ? _settleValue("autoPowerOff", status.autoPowerOff) : ""
    autoPowerOffOptions = Model.selectOptions(parsed.schema, Model.SETTING_AUTO_POWER_OFF)
    touchToneSupported = status.touchToneSupported
    touchTone = status.touchToneSupported ? _settleValue("touchTone", status.touchTone) : false
    lowBatteryPromptSupported = status.lowBatteryPromptSupported
    lowBatteryPrompt = status.lowBatteryPromptSupported ? _settleValue("lowBatteryPrompt", status.lowBatteryPrompt) : false
    deviceInfo = {
      firmwareLeft: String((parsed.values || {}).firmwareVersionLeft || ""),
      firmwareRight: String((parsed.values || {}).firmwareVersionRight || ""),
      serial: String((parsed.values || {}).serialNumber || ""),
      tws: String((parsed.values || {}).twsStatus || ""),
      host: String((parsed.values || {}).hostDevice || ""),
      wind: String((parsed.values || {}).windNoiseDetected || ""),
      adaptive: String((parsed.values || {}).adaptiveNoiseCanceling || "")
    }
    limitHighVolumeSupported = status.limitHighVolumeSupported
    limitHighVolume = status.limitHighVolumeSupported
      ? _settleValue("limitHighVolume", status.limitHighVolume) : false
    limitDbSupported = status.limitDbSupported
    limitDb = status.limitDbSupported
      ? _settleValue("limitDb", status.limitDb) : Model.LEVEL_UNKNOWN
    limitDbOptions = Model.integerRangeOptions(parsed.schema, Model.SETTING_LIMIT_HIGH_VOLUME_DB, " dB")
    limitRateSupported = status.limitRateSupported
    limitRate = status.limitRateSupported
      ? _settleValue("limitRate", status.limitRate) : ""
    limitRateOptions = Model.selectOptions(parsed.schema, Model.SETTING_LIMIT_HIGH_VOLUME_RATE)
    var buttons = Model.buttonSettings(parsed.schema, parsed.values || {})
    buttonBindings = buttons.bindings
    buttonOptions = buttons.options
    buttonResetSupported = buttons.resetSupported
    dualConnectionsSupported = status.dualConnectionsSupported
    dualConnections = status.dualConnectionsSupported
      ? _settleValue("dualConnections", status.dualConnections) : false
    dualConnectionsDevicesSupported = status.dualConnectionsDevicesSupported
    dualConnectionsDevices = status.dualConnectionsDevicesSupported
      ? _settleValue("dualConnectionsDevices", status.dualConnectionsDevices) : []
    dualConnectionsOptions = _settleValue("dualConnectionsOptions", Model.selectOptions(parsed.schema, Model.SETTING_DUAL_CONNECTIONS_DEVICES))

    _checkLowBattery("leftLowNotified", "Left earbud", leftLevel, leftCharging)
    _checkLowBattery("rightLowNotified", "Right earbud", rightLevel, rightCharging)
    _checkLowBattery("caseLowNotified", "Case", caseLevel, false)
    refreshCodec()
  }

  function _noteReadError(message) {
    statusStale = true
    lastError = message + (connected ? " Showing last known values." : " Retry with R.")
  }

  function _clearWrites() {
    _actionQueue = []
    queuedActions = 0
    _pendingMode = ""
    _windNoisePending = false
    _pendingWrites = {}
    settleTimer.stop()
    windNoiseSettleTimer.stop()
    pendingSettleTimer.stop()
  }

  function _enqueue(command) {
    _actionQueue.push(command)
    queuedActions = _actionQueue.length
    settleTimer.stop()
    windNoiseSettleTimer.stop()
    pendingSettleTimer.stop()
    actionStatusTimer.stop()
    actionStatus = ""
    _pumpActions()
  }

  function _pumpActions() {
    if (statusProcess.running || actionProcess.running || transferProcess.running || !queuedActions) return
    var command = _actionQueue.shift()
    queuedActions = _actionQueue.length
    if (!connected || command[1] !== discoveredMac) { _clearWrites(); return }
    actionProcess.command = command
    actionProcess.running = true
    actionWatchdog.interval = command[0] === ldacScript ? 40000 : 15000
    actionWatchdog.restart()
  }

  function setEqPreset(value) {
    if (!connected || discoveredMac === "" || !eqOptions.some(function (o) { return o.value === value })) return
    _beginWrite("eqPreset", value)
    var command = [setScript, discoveredMac]
    if (spatialAudioSupported) {
      _beginWrite("spatialAudio", false)
      command.push(Model.SETTING_SPATIAL_AUDIO + "=false")
    }
    command.push(Model.SETTING_EQ_PRESET + "=" + value)
    _enqueue(command)
  }

  function _customEqCommand() {
    var command = [setScript, discoveredMac]
    if (spatialAudioSupported) {
      _beginWrite("spatialAudio", false)
      command.push(Model.SETTING_SPATIAL_AUDIO + "=false")
    }
    _beginWrite("eqPreset", "")
    return command
  }

  function setCustomEqBands(values) {
    var bands = Model.normalizeEqBands(values, eqSpec)
    if (!connected || !discoveredMac || !customEqSupported || !bands) return
    var command = _customEqCommand()
    _beginWrite("eqBands", bands)
    _beginWrite("customEqProfile", "")
    command.push(Model.SETTING_EQ_BANDS + "=" + bands.join(","))
    _enqueue(command)
  }

  function setCustomEqBand(index, value) {
    if (!Number.isInteger(index) || index < 0 || index >= eqBands.length) return
    var bands = eqBands.slice()
    bands[index] = value
    setCustomEqBands(bands)
  }

  function loadCustomEqProfile(name) {
    if (!connected || !discoveredMac || !customEqSupported ||
        !customEqOptions.some(function (o) { return o.value === name })) return
    var command = _customEqCommand()
    _beginWrite("customEqProfile", name)
    command.push(Model.SETTING_CUSTOM_EQ + "=" + Model.customProfileValue(name))
    _enqueue(command)
  }

  function saveCustomEqProfile(name) {
    name = String(name || "").trim()
    var bands = Model.normalizeEqBands(eqBands, eqSpec)
    if (!connected || !discoveredMac || !customEqSupported || !customEqProfilesSupported || !bands ||
        !name || name.length > 64 || /[\x00-\x1f]/.test(name)) return false
    var command = _customEqCommand()
    _beginWrite("customEqProfile", name)
    command.push(Model.SETTING_EQ_BANDS + "=" + bands.join(","))
    command.push(Model.SETTING_CUSTOM_EQ + "=+" + name)
    _enqueue(command)
    return true
  }

  function _noteDisconnected(message) {
    _clearWrites()
    if (connected) _notify("Soundcore earbuds disconnected", message, "normal")
    connected = false
    lastError = message
    discoveredMac = ""
    hostCodec = ""
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
    notifyProcess.command = ["omarchy-notification-send", "--app-name", "Omacore", "-i", next.icon || notificationIcon, "-u", next.urgency, next.headline, next.description]
    if (next.exec) notifyProcess.command = notifyProcess.command.concat(["--exec"].concat(next.exec))
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
    if (mode === "" || !connected || discoveredMac === "") return
    _pendingMode = mode
    ancMode = mode
    settleTimer.restart()
    _enqueue([setScript, discoveredMac, Model.SETTING_AMBIENT_SOUND_MODE + "=" + mode])
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
    if (!connected || !windNoiseSuppressionSupported || discoveredMac === "") return
    _windNoisePending = true
    _pendingWindNoiseValue = enabled
    windNoiseSuppression = enabled
    windNoiseSettleTimer.restart()
    _enqueue([setScript, discoveredMac, Model.SETTING_WIND_NOISE_SUPPRESSION + "=" + (enabled ? "true" : "false")])
  }

  function _settleValue(propName, reported) {
    if (!(propName in _pendingWrites)) return reported
    if (JSON.stringify(reported) === JSON.stringify(_pendingWrites[propName])) {
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
    if (mode === "" || !connected || !noiseCancelingModeSupported || discoveredMac === "") return
    _beginWrite("noiseCancelingMode", mode)
    _enqueue([setScript, discoveredMac, Model.SETTING_NOISE_CANCELING_MODE + "=" + mode])
  }

  function setManualNoiseCancelingLevel(level) {
    if (!connected || !manualNoiseCancelingSupported || discoveredMac === "") return
    var clamped = Math.max(Model.MANUAL_LEVEL_MIN, Math.min(Model.MANUAL_LEVEL_MAX, Math.round(level)))
    _beginWrite("manualNoiseCancelingLevel", clamped)
    _enqueue([setScript, discoveredMac, Model.SETTING_MANUAL_NOISE_CANCELING + "=" + clamped])
  }

  function setMultiSceneNoiseCanceling(scene) {
    if (scene === "" || !connected || !multiSceneNoiseCancelingSupported || discoveredMac === "") return
    _beginWrite("multiSceneNoiseCanceling", scene)
    _enqueue([setScript, discoveredMac, Model.SETTING_MULTI_SCENE_NOISE_CANCELING + "=" + scene])
  }

  function setRealTimeAdaptiveNoiseCanceling(enabled) {
    if (!connected || !realTimeAdaptiveNoiseCancelingSupported || discoveredMac === "") return
    _beginWrite("realTimeAdaptiveNoiseCanceling", enabled)
    _enqueue([setScript, discoveredMac, Model.SETTING_REALTIME_ADAPTIVE_NOISE_CANCELING + "=" + (enabled ? "true" : "false")])
  }

  function setTransparencyMode(mode) {
    if (mode === "" || !connected || !transparencyModeSupported || discoveredMac === "") return
    _beginWrite("transparencyMode", mode)
    _enqueue([setScript, discoveredMac, Model.SETTING_TRANSPARENCY_MODE + "=" + mode])
  }

  function setSoundEffect(effect) {
    if (effect === "" || !connected || !spatialAudioSupported || discoveredMac === "") return
    if (effect === Model.SOUND_EFFECT_OFF) {
      _beginWrite("spatialAudio", false)
      _enqueue([setScript, discoveredMac, Model.SETTING_SPATIAL_AUDIO + "=false"])
      return
    }
    if (!spatialAudioModeSupported) return
    var turnOffLdac = ldacSupported && ldacEnabled
    if (turnOffLdac) {
      _beginWrite("ldacEnabled", false)
    }
    _beginWrite("spatialAudio", true)
    _beginWrite("spatialAudioMode", effect)
    var command = [setScript, discoveredMac]
    if (turnOffLdac) command.push(Model.SETTING_LDAC + "=false")
    command.push(
      Model.SETTING_SPATIAL_AUDIO + "=true",
      Model.SETTING_SPATIAL_AUDIO_MODE + "=" + effect)
    _enqueue(command)
  }

  function setLdac(enabled) {
    if (!connected || !ldacSupported || discoveredMac === "" || updating) return
    _enqueue([ldacScript, discoveredMac, enabled ? "true" : "false"])
  }

  function setAutoPowerOff(value) {
    if (!connected || !autoPowerOffSupported || discoveredMac === "" ||
        !autoPowerOffOptions.some(function (option) { return option.value === value })) return
    _beginWrite("autoPowerOff", value)
    _enqueue([setScript, discoveredMac, Model.SETTING_AUTO_POWER_OFF + "=" + value])
  }

  function setTouchTone(enabled) {
    if (!connected || !touchToneSupported || discoveredMac === "") return
    _beginWrite("touchTone", enabled)
    _enqueue([setScript, discoveredMac, Model.SETTING_TOUCH_TONE + "=" + (enabled ? "true" : "false")])
  }

  function transferEq(operation) {
    if (!connected || !eqTransferSupported || discoveredMac === "" || busy || updating) return
    transferProcess.command = [eqTransferScript, operation, discoveredMac]
    transferProcess.running = true
    transferWatchdog.restart()
  }

  function setLowBatteryPrompt(enabled) {
    if (!connected || !lowBatteryPromptSupported || discoveredMac === "") return
    _beginWrite("lowBatteryPrompt", enabled)
    _enqueue([setScript, discoveredMac, Model.SETTING_LOW_BATTERY_PROMPT + "=" + (enabled ? "true" : "false")])
  }

  function setHighVolumeLimit(enabled) {
    if (!connected || !limitHighVolumeSupported || discoveredMac === "") return
    _beginWrite("limitHighVolume", enabled)
    _enqueue([setScript, discoveredMac, Model.SETTING_LIMIT_HIGH_VOLUME + "=" + (enabled ? "true" : "false")])
  }

  function setLimitDb(value) {
    if (!connected || !limitDbSupported || discoveredMac === "" ||
        !limitDbOptions.some(function (option) { return option.value === value })) return
    _beginWrite("limitDb", value)
    _enqueue([setScript, discoveredMac, Model.SETTING_LIMIT_HIGH_VOLUME_DB + "=" + value])
  }

  function setLimitRate(value) {
    if (!connected || !limitRateSupported || discoveredMac === "" ||
        !limitRateOptions.some(function (option) { return option.value === value })) return
    _beginWrite("limitRate", value)
    _enqueue([setScript, discoveredMac, Model.SETTING_LIMIT_HIGH_VOLUME_RATE + "=" + value])
  }

  function setButtonBinding(id, value) {
    if (!connected || discoveredMac === "" || statusStale || updating) return
    var choices = buttonOptions[id] || []
    if (!choices.some(function (option) { return option.value === value })) return
    if (buttonBindings[id] === value) return
    _enqueue([setScript, discoveredMac, id + "=" + value])
  }

  function resetButtonBindings() {
    if (!connected || discoveredMac === "" || statusStale || updating || !buttonResetSupported || !hasButtonControls) return
    _enqueue([setScript, discoveredMac, Model.SETTING_RESET_BUTTONS])
  }

  function setDualConnections(enabled) {
    if (!connected || !dualConnectionsSupported || discoveredMac === "") return
    _beginWrite("dualConnections", enabled)
    _enqueue([setScript, discoveredMac, Model.SETTING_DUAL_CONNECTIONS + "=" + (enabled ? "true" : "false")])
  }

  function setDeviceConnection(mac, enabled) {
    if (!connected || !dualConnections || !individualConnectionsSupported || updating || statusStale ||
        !dualConnectionsOptions.some(function (option) { return option.value === mac })) return
    var devices = dualConnectionsDevices.slice()
    var index = devices.indexOf(mac)
    if ((index >= 0) === enabled) return
    if (enabled && devices.length >= 2) {
      actionStatusError = true
      actionStatus = "Disconnect one device before connecting another."
      actionStatusTimer.restart()
      return
    }
    if (enabled) devices.push(mac)
    else devices.splice(index, 1)
    _beginWrite("dualConnectionsDevices", devices)
    _enqueue([pluginDir + "/omacore-connection", discoveredMac, deviceModel, mac, enabled ? "true" : "false"])
  }

  function removeDualConnectionsDevice(mac) {
    if (!connected || updating || statusStale || !dualConnectionsDevicesSupported || discoveredMac === "" ||
        dualConnectionsDevices.indexOf(mac) >= 0 || !dualConnectionsOptions.some(function (option) { return option.value === mac })) return
    _beginWrite("dualConnectionsOptions", dualConnectionsOptions.filter(function (option) { return option.value !== mac }))
    _enqueue([setScript, discoveredMac, Model.SETTING_DUAL_CONNECTIONS_DEVICES + "=-" + mac])
  }

  Timer {
    id: transferWatchdog
    interval: 15000
    onTriggered: if (transferProcess.running) transferProcess.running = false
  }

  Timer {
    id: actionWatchdog
    interval: 15000
    onTriggered: if (actionProcess.running) actionProcess.running = false
  }

  Timer {
    id: pollTimer
    interval: root.liveUpdates ? 3000 : root.pollIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 3000
    running: root.panelOpen && root.connected && root.ldacSupported
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshCodec()
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
    id: transferProcess
    running: false
    command: []
    stdout: StdioCollector { id: transferOut; waitForEnd: true }
    stderr: StdioCollector { id: transferErr; waitForEnd: true }
    onExited: function (exitCode) {
      transferWatchdog.stop()
      root.actionStatusError = exitCode !== 0
      root.actionStatus = exitCode === 0
        ? Model.elideError(transferOut.text).trim()
        : "EQ transfer failed: " + (Model.elideError(transferErr.text) || "command failed")
      actionStatusTimer.restart()
      root.refresh()
      root._pumpActions()
    }
  }

  Process {
    id: codecProcess
    running: false
    command: []
    stdout: StdioCollector { id: codecOut; waitForEnd: true }
    onExited: function (exitCode) {
      if (root.codecRequestedMac === root.discoveredMac)
        root.hostCodec = exitCode === 0 ? Model.parseCodec(codecOut.text) : ""
      else root.refreshCodec()
    }
  }

  Process {
    id: deviceChoiceProcess
    running: false
    command: []
    stderr: StdioCollector { id: deviceChoiceErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.actionStatusError = true
        root.actionStatus = "Device selection failed: " + (Model.elideError(deviceChoiceErr.text) || "could not save the setting")
        actionStatusTimer.restart()
      }
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
      pollWatchdog.stop()
      if (exitCode === 0) root.applyStatus(statusOut.text)
      else root._noteReadError(Model.elideError(statusErr.text) || "Status refresh failed or timed out.")
      root._pumpActions()
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
      actionWatchdog.stop()
      if (exitCode !== 0) {
        root._clearWrites()
        root.actionStatusError = true
        root.actionStatus = "Update failed: " + (Model.elideError(actionErr.text) || "command failed or timed out")
        actionStatusTimer.restart()
      } else if (root.queuedActions > 0) {
        root._pumpActions()
        return
      } else {
        root.actionStatus = ""
        if (root._pendingMode !== "") settleTimer.restart()
        if (root._windNoisePending) windNoiseSettleTimer.restart()
        if (Object.keys(root._pendingWrites).length) pendingSettleTimer.restart()
      }
      root.refresh()
    }
  }

  Process {
    id: registerProcess
    running: false
    command: []
    stderr: StdioCollector { id: registerErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (root.registering) {
        root.registering = false
        if (exitCode === 0) {
          root._notify("Device registered", root.unregisteredName + " is now registered with OpenSCQ30 — this widget will connect to it on the next poll.", "normal")
        } else {
          root._registerFailedAt = Date.now()
          root._notify("Registration failed", Model.elideError(registerErr.text) || "Try picking a different model in the panel, or add the device manually.", "normal")
        }
      }
      root.refresh()
    }
  }

  Process {
    id: installProcess
    running: false
    command: []
    stderr: StdioCollector { id: installErr; waitForEnd: true }
    onExited: function (exitCode) {
      if (root.cliInstalling) {
        root.cliInstalling = false
        if (exitCode === 0) {
          root._notify("OpenSCQ30 installed", "The OpenSCQ30 CLI is ready — this widget will find it automatically.", "normal")
        } else {
          root._notify("OpenSCQ30 install failed", Model.elideError(installErr.text) || "Try the panel's Install button to run it in a terminal.", "normal")
        }
      }
      root.refresh()
    }
  }
}
