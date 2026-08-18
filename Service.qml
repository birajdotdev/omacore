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
  property string lastError: ""
  property string actionStatus: ""

  readonly property string macAddress: String(setting("macAddress", "") || "").trim()
  readonly property int pollIntervalSec: intSetting("pollIntervalSec", 30, 10, 300)
  readonly property string ctlPath: String(setting("ctlPath", "") || "").trim()
  readonly property string resolvedBin: ctlPath !== "" ? ctlPath : "openscq30"
  readonly property bool busy: statusProcess.running || actionProcess.running
  readonly property bool hasEarbuds: connected

  // Held over an incoming poll until the CLI agrees, so a write already in
  // flight when the click landed cannot snap the control back.
  property string _pendingMode: ""
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
      connected = false
      lastError = "Could not read the earbuds' status."
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
      else {
        root.connected = false
        root.lastError = Model.elideError(statusErr.text) || "Could not reach the earbuds."
      }
    }
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
        root.actionStatus = Model.elideError(actionErr.text) || "openscq30 rejected the command"
        actionStatusTimer.restart()
      }
      root.refresh()
    }
  }
}
