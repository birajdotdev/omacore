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

// Sub-settings under NoiseCanceling / Transparency ambient sound modes, and the
// Sound Effects (spatial audio) settings, all confirmed present on D1202/D1202C via
// `openscq30 device -a <mac> list-settings --json`. Same speculative-polling caveat
// as windNoiseSuppression applies to each: only add a settingId here once you have
// confirmed (via list-settings) that every model this widget targets exposes it —
// unlike an Information setting simply being absent from the reply, a settingId the
// device's schema does not know about at all fails the *entire* -g batch.
var SETTING_TRANSPARENCY_MODE = "transparencyMode"
var SETTING_NOISE_CANCELING_MODE = "noiseCancelingMode"
var SETTING_MANUAL_NOISE_CANCELING = "manualNoiseCanceling"
var SETTING_MULTI_SCENE_NOISE_CANCELING = "multiSceneNoiseCanceling"
var SETTING_REALTIME_ADAPTIVE_NOISE_CANCELING = "realTimeAdaptiveNoiseCanceling"
var SETTING_SPATIAL_AUDIO = "spatialAudio"
var SETTING_SPATIAL_AUDIO_MODE = "spatialAudioMode"

// The settings this widget polls on every refresh.
var POLL_SETTING_IDS = [
  SETTING_AMBIENT_SOUND_MODE,
  SETTING_BATTERY_LEFT,
  SETTING_BATTERY_RIGHT,
  SETTING_BATTERY_CASE,
  SETTING_CHARGING_LEFT,
  SETTING_CHARGING_RIGHT,
  SETTING_WIND_NOISE_SUPPRESSION,
  SETTING_TRANSPARENCY_MODE,
  SETTING_NOISE_CANCELING_MODE,
  SETTING_MANUAL_NOISE_CANCELING,
  SETTING_MULTI_SCENE_NOISE_CANCELING,
  SETTING_REALTIME_ADAPTIVE_NOISE_CANCELING,
  SETTING_SPATIAL_AUDIO,
  SETTING_SPATIAL_AUDIO_MODE
]

// AmbientSoundMode's three raw values on the D1202/D1202C (R60i NC / P31i),
// in the order OpenSCQ30's own enum declares them.
var MODE_NOISE_CANCELING = "NoiseCanceling"
var MODE_TRANSPARENCY = "Transparency"
var MODE_NORMAL = "Normal"
var MODES = [MODE_NOISE_CANCELING, MODE_TRANSPARENCY, MODE_NORMAL]

// TransparencyMode's raw values, shown only while ambientSoundMode is Transparency.
var TRANSPARENCY_FULLY = "FullyTransparent"
var TRANSPARENCY_VOCAL = "VocalMode"
var TRANSPARENCY_MODES = [TRANSPARENCY_FULLY, TRANSPARENCY_VOCAL]

// NoiseCancelingMode's raw values, shown only while ambientSoundMode is NoiseCanceling.
var NC_MODE_MANUAL = "Manual"
var NC_MODE_ADAPTIVE = "Adaptive"
var NC_MODE_MULTI_SCENE = "MultiScene"
var NC_SUBMODES = [NC_MODE_MANUAL, NC_MODE_ADAPTIVE, NC_MODE_MULTI_SCENE]

// manualNoiseCanceling's i32Range bounds (confirmed via list-settings: start 1, end 5).
var MANUAL_LEVEL_MIN = 1
var MANUAL_LEVEL_MAX = 5

// MultiSceneNoiseCanceling's raw values, shown only while noiseCancelingMode is MultiScene.
var SCENE_TRANSPORT = "Transport"
var SCENE_OUTDOOR = "Outdoor"
var SCENE_INDOOR = "Indoor"
var SCENES = [SCENE_TRANSPORT, SCENE_OUTDOOR, SCENE_INDOOR]

// Sound Effects (Soundcore's spatial audio). The panel only offers these
// three — picking one sets spatialAudio=true and spatialAudioMode=<value>
// together. SOUND_EFFECT_OFF isn't offered as a button; it's the sentinel
// Service.soundEffect reports when spatialAudio is off (e.g. set that way
// outside this widget), so nothing shows selected rather than showing "Off".
var SOUND_EFFECT_OFF = "Off"
var SOUND_EFFECT_MUSIC = "Music"
var SOUND_EFFECT_MOVIE = "Movie"
var SOUND_EFFECT_GAMING = "Gaming"
var SOUND_EFFECTS = [SOUND_EFFECT_MUSIC, SOUND_EFFECT_MOVIE, SOUND_EFFECT_GAMING]

// Level the widget shows when a fraction failed to parse or the setting was absent.
var LEVEL_UNKNOWN = -1

var MAX_ERROR_CHARS = 140
var ELIDED_ERROR_CHARS = 137

// Friendly names for the "OpenSCQ30 model id" setting (manifest.json's `model`),
// so the panel can show which earbuds these are rather than a generic "Soundcore".
// Covers only the two models this widget actually targets — see README.
function modelDisplayName(modelId) {
  if (modelId === "SoundcoreD1202C") return "Soundcore R60i NC"
  if (modelId === "SoundcoreD1202") return "Soundcore P31i"
  return "Soundcore"
}

function modeLabel(mode) {
  if (mode === MODE_NOISE_CANCELING) return "Noise Cancellation"
  if (mode === MODE_TRANSPARENCY) return "Transparency"
  if (mode === MODE_NORMAL) return "Normal"
  return "Unknown"
}

function transparencyModeLabel(mode) {
  if (mode === TRANSPARENCY_FULLY) return "Fully Transparent"
  if (mode === TRANSPARENCY_VOCAL) return "Vocal Mode"
  return "Unknown"
}

function ncSubModeLabel(mode) {
  if (mode === NC_MODE_MANUAL) return "Manual"
  if (mode === NC_MODE_ADAPTIVE) return "Adaptive"
  if (mode === NC_MODE_MULTI_SCENE) return "Multi-Scene"
  return "Unknown"
}

function sceneLabel(scene) {
  if (scene === SCENE_TRANSPORT) return "Transport"
  if (scene === SCENE_OUTDOOR) return "Outdoor"
  if (scene === SCENE_INDOOR) return "Indoor"
  return "Unknown"
}

function soundEffectLabel(effect) {
  if (effect === SOUND_EFFECT_OFF) return "Off"
  if (effect === SOUND_EFFECT_MUSIC) return "Music"
  if (effect === SOUND_EFFECT_MOVIE) return "Movie"
  if (effect === SOUND_EFFECT_GAMING) return "Gaming"
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

function has(map, id) {
  return Object.prototype.hasOwnProperty.call(map, id)
}

// manualNoiseCanceling arrives as a JSON number already (i32Range), unlike the
// string-typed Select/Information settings elsewhere in this file.
function levelFromNumber(value) {
  var n = typeof value === "number" ? value : parseInt(value, 10)
  if (!isFinite(n)) return LEVEL_UNKNOWN
  return Math.max(MANUAL_LEVEL_MIN, Math.min(MANUAL_LEVEL_MAX, Math.round(n)))
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
    windNoiseSuppression: false,
    transparencyModeSupported: false,
    transparencyMode: "",
    noiseCancelingModeSupported: false,
    noiseCancelingMode: "",
    manualNoiseCancelingSupported: false,
    manualNoiseCancelingLevel: LEVEL_UNKNOWN,
    multiSceneNoiseCancelingSupported: false,
    multiSceneNoiseCanceling: "",
    realTimeAdaptiveNoiseCancelingSupported: false,
    realTimeAdaptiveNoiseCanceling: false,
    spatialAudioSupported: false,
    spatialAudio: false,
    spatialAudioModeSupported: false,
    spatialAudioMode: ""
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

  status.windNoiseSuppressionSupported = has(map, SETTING_WIND_NOISE_SUPPRESSION)
  status.windNoiseSuppression = boolFromToggle(map[SETTING_WIND_NOISE_SUPPRESSION])

  status.transparencyModeSupported = has(map, SETTING_TRANSPARENCY_MODE)
  status.transparencyMode = String(map[SETTING_TRANSPARENCY_MODE] || "")

  status.noiseCancelingModeSupported = has(map, SETTING_NOISE_CANCELING_MODE)
  status.noiseCancelingMode = String(map[SETTING_NOISE_CANCELING_MODE] || "")

  status.manualNoiseCancelingSupported = has(map, SETTING_MANUAL_NOISE_CANCELING)
  status.manualNoiseCancelingLevel = levelFromNumber(map[SETTING_MANUAL_NOISE_CANCELING])

  status.multiSceneNoiseCancelingSupported = has(map, SETTING_MULTI_SCENE_NOISE_CANCELING)
  status.multiSceneNoiseCanceling = String(map[SETTING_MULTI_SCENE_NOISE_CANCELING] || "")

  status.realTimeAdaptiveNoiseCancelingSupported = has(map, SETTING_REALTIME_ADAPTIVE_NOISE_CANCELING)
  status.realTimeAdaptiveNoiseCanceling = boolFromToggle(map[SETTING_REALTIME_ADAPTIVE_NOISE_CANCELING])

  status.spatialAudioSupported = has(map, SETTING_SPATIAL_AUDIO)
  status.spatialAudio = boolFromToggle(map[SETTING_SPATIAL_AUDIO])

  status.spatialAudioModeSupported = has(map, SETTING_SPATIAL_AUDIO_MODE)
  status.spatialAudioMode = String(map[SETTING_SPATIAL_AUDIO_MODE] || "")

  return status
}

// Collapse the CLI's stderr into one line the panel can show inside a row.
function elideError(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > MAX_ERROR_CHARS ? value.substring(0, ELIDED_ERROR_CHARS) + "…" : value
}
