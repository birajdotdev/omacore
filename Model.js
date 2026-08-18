// No QML imports on purpose, so every function here runs in a plain JS harness.

// OpenSCQ30 SettingId values (camelCase, as the CLI's -g/-s flags expect).
var SETTING_AMBIENT_SOUND_MODE = "ambientSoundMode"
var SETTING_BATTERY_LEFT = "batteryLevelLeft"
var SETTING_BATTERY_RIGHT = "batteryLevelRight"
var SETTING_BATTERY_CASE = "caseBatteryLevel"
var SETTING_CHARGING_LEFT = "isChargingLeft"
var SETTING_CHARGING_RIGHT = "isChargingRight"
// Toggle setting, present only on models/firmware that support it (D1202/D1202C do).
// Absent from -g's reply rather than erroring, so it's polled speculatively like the rest.
var SETTING_WIND_NOISE_SUPPRESSION = "windNoiseSuppression"

// The settings this widget polls on every refresh.
var POLL_SETTING_IDS = [
  SETTING_AMBIENT_SOUND_MODE,
  SETTING_BATTERY_LEFT,
  SETTING_BATTERY_RIGHT,
  SETTING_BATTERY_CASE,
  SETTING_CHARGING_LEFT,
  SETTING_CHARGING_RIGHT,
  SETTING_WIND_NOISE_SUPPRESSION
]

// AmbientSoundMode's three raw values on the D1202/D1202C (R60i NC / P31i),
// in the order OpenSCQ30's own enum declares them.
var MODE_NOISE_CANCELING = "NoiseCanceling"
var MODE_TRANSPARENCY = "Transparency"
var MODE_NORMAL = "Normal"
var MODES = [MODE_NOISE_CANCELING, MODE_TRANSPARENCY, MODE_NORMAL]

// Level the widget shows when a fraction failed to parse or the setting was absent.
var LEVEL_UNKNOWN = -1

var MAX_ERROR_CHARS = 140
var ELIDED_ERROR_CHARS = 137

function modeLabel(mode) {
  if (mode === MODE_NOISE_CANCELING) return "Noise Cancellation"
  if (mode === MODE_TRANSPARENCY) return "Transparency"
  if (mode === MODE_NORMAL) return "Normal"
  return "Unknown"
}

// Battery values on this device arrive as "raw/max" (e.g. "8/10"), not a percent,
// because the hardware only reports ten discrete steps. See setting_handler.rs
// in OpenSCQ30's dual_battery and case_battery_level modules.
function levelFromFraction(text) {
  var value = String(text || "")
  var parts = value.split("/")
  if (parts.length !== 2) return LEVEL_UNKNOWN
  var raw = parseInt(parts[0], 10)
  var max = parseInt(parts[1], 10)
  if (!isFinite(raw) || !isFinite(max) || max <= 0) return LEVEL_UNKNOWN
  return Math.max(0, Math.min(100, Math.round((raw / max) * 100)))
}

function levelText(level) {
  return level === LEVEL_UNKNOWN ? "--" : String(level) + "%"
}

function levelFraction(level) {
  if (level === LEVEL_UNKNOWN) return 0
  return Math.max(0, Math.min(100, level)) / 100
}

// isChargingLeft/Right are OpenSCQ30 Information settings, so their `value` is
// a literal string rather than a JSON boolean. Confirmed live against a
// R60i NC on openscq30 2.11.0: it reports "Yes"/"No", not "true"/"false".
function boolFromString(text) {
  return String(text || "").toLowerCase() === "yes"
}

// windNoiseSuppression is a Toggle setting, so unlike isChargingLeft/Right (Information
// settings, which come through as the literal string "Yes"/"No"), its value.value in the
// CLI's JSON is a real JSON boolean already. See Value's serde tagging in openscq30-lib.
function boolFromToggle(value) {
  return value === true
}

// `openscq30 device -a <mac> setting -g <id> [-g <id> ...] --json` prints:
// [{"settingId":"ambientSoundMode","value":{"type":"string","value":"NoiseCanceling"}}, ...]
// Every setting used here (Select and Information) converts to Value::String
// on the Rust side, so `.value.value` is always a string.
function parseSettingsJson(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, map: {} }

  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return { ok: false, map: {} }
  }
  if (!Array.isArray(parsed)) return { ok: false, map: {} }

  var map = {}
  for (var i = 0; i < parsed.length; i++) {
    var entry = parsed[i]
    if (!entry || typeof entry !== "object") continue
    var id = entry.settingId
    var value = entry.value
    if (typeof id !== "string" || !value || typeof value !== "object") continue
    map[id] = value.value
  }
  return { ok: true, map: map }
}

// Full shape on every path, so the panel never reads undefined off a parse failure.
function defaultStatus() {
  return {
    ok: false,
    ancMode: "",
    leftLevel: LEVEL_UNKNOWN,
    rightLevel: LEVEL_UNKNOWN,
    caseLevel: LEVEL_UNKNOWN,
    leftCharging: false,
    rightCharging: false,
    windNoiseSuppressionSupported: false,
    windNoiseSuppression: false
  }
}

function statusFromMap(map) {
  var status = defaultStatus()
  status.ok = true
  status.ancMode = String(map[SETTING_AMBIENT_SOUND_MODE] || "")
  status.leftLevel = levelFromFraction(map[SETTING_BATTERY_LEFT])
  status.rightLevel = levelFromFraction(map[SETTING_BATTERY_RIGHT])
  status.caseLevel = levelFromFraction(map[SETTING_BATTERY_CASE])
  status.leftCharging = boolFromString(map[SETTING_CHARGING_LEFT])
  status.rightCharging = boolFromString(map[SETTING_CHARGING_RIGHT])
  status.windNoiseSuppressionSupported = Object.prototype.hasOwnProperty.call(map, SETTING_WIND_NOISE_SUPPRESSION)
  status.windNoiseSuppression = boolFromToggle(map[SETTING_WIND_NOISE_SUPPRESSION])
  return status
}

// Collapse the CLI's stderr into one line the panel can show inside a row.
function elideError(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > MAX_ERROR_CHARS ? value.substring(0, ELIDED_ERROR_CHARS) + "…" : value
}
