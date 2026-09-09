// No QML imports on purpose, so every function here runs in a plain JS harness.

// OpenSCQ30 SettingId values (camelCase, as the CLI's -g/-s flags expect).
// These IDs are stable across models — the same setting always has the same ID.
var SETTING_AMBIENT_SOUND_MODE = "ambientSoundMode"
var SETTING_BATTERY_LEFT = "batteryLevelLeft"
var SETTING_BATTERY_RIGHT = "batteryLevelRight"
var SETTING_BATTERY_CASE = "caseBatteryLevel"
var SETTING_CHARGING_LEFT = "isChargingLeft"
var SETTING_CHARGING_RIGHT = "isChargingRight"
var SETTING_WIND_NOISE_SUPPRESSION = "windNoiseSuppression"
var SETTING_TRANSPARENCY_MODE = "transparencyMode"
var SETTING_NOISE_CANCELING_MODE = "noiseCancelingMode"
var SETTING_MANUAL_NOISE_CANCELING = "manualNoiseCanceling"
var SETTING_MULTI_SCENE_NOISE_CANCELING = "multiSceneNoiseCanceling"
var SETTING_REALTIME_ADAPTIVE_NOISE_CANCELING = "realTimeAdaptiveNoiseCanceling"
var SETTING_SPATIAL_AUDIO = "spatialAudio"
var SETTING_SPATIAL_AUDIO_MODE = "spatialAudioMode"

// AmbientSoundMode values — confirmed present on D1202/D1202C.
var MODE_NOISE_CANCELING = "NoiseCanceling"
var MODE_TRANSPARENCY = "Transparency"
var MODE_NORMAL = "Normal"
var MODES = [MODE_NOISE_CANCELING, MODE_TRANSPARENCY, MODE_NORMAL]

var TRANSPARENCY_FULLY = "FullyTransparent"
var TRANSPARENCY_VOCAL = "VocalMode"
var TRANSPARENCY_MODES = [TRANSPARENCY_FULLY, TRANSPARENCY_VOCAL]

var NC_MODE_MANUAL = "Manual"
var NC_MODE_ADAPTIVE = "Adaptive"
var NC_MODE_MULTI_SCENE = "MultiScene"
var NC_SUBMODES = [NC_MODE_MANUAL, NC_MODE_ADAPTIVE, NC_MODE_MULTI_SCENE]

var MANUAL_LEVEL_MIN = 1
var MANUAL_LEVEL_MAX = 5

var SCENE_TRANSPORT = "Transport"
var SCENE_OUTDOOR = "Outdoor"
var SCENE_INDOOR = "Indoor"
var SCENES = [SCENE_TRANSPORT, SCENE_OUTDOOR, SCENE_INDOOR]

var SOUND_EFFECT_OFF = "Off"
var SOUND_EFFECT_MUSIC = "Music"
var SOUND_EFFECT_MOVIE = "Movie"
var SOUND_EFFECT_GAMING = "Gaming"
var SOUND_EFFECTS = [SOUND_EFFECT_MUSIC, SOUND_EFFECT_MOVIE, SOUND_EFFECT_GAMING]

var LEVEL_UNKNOWN = -1

var MAX_ERROR_CHARS = 140
var ELIDED_ERROR_CHARS = 137

// --- Display helpers ---

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

// --- Battery helpers ---

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

// --- Value parsers ---

// isChargingLeft/Right are OpenSCQ30 Information settings, so their value is
// a literal string ("Yes"/"No"), not a JSON boolean.
function boolFromString(text) {
  return String(text || "").toLowerCase() === "yes"
}

// windNoiseSuppression is a Toggle setting — value is a real JSON boolean.
function boolFromToggle(value) {
  return value === true
}

function levelFromNumber(value) {
  var n = typeof value === "number" ? value : parseInt(value, 10)
  if (!isFinite(n)) return LEVEL_UNKNOWN
  return Math.max(MANUAL_LEVEL_MIN, Math.min(MANUAL_LEVEL_MAX, Math.round(n)))
}

// --- Status parsing ---

function has(map, id) {
  return Object.prototype.hasOwnProperty.call(map, id)
}

// Options for the panel's "register this device" model dropdown, fed by the
// `models` array omacore-status includes with the registeredMissing status.
function modelOptions(models) {
  return (models || []).map(function (m) {
    return { value: m.model, label: m.name + " (" + m.model + ")" }
  })
}

// Parse the JSON output from omacore-status.
// Returns { connected, mac, name, model, schema, values } or
// { connected: false } if nothing is connected.
function parseStatus(raw) {
  try {
    var parsed = JSON.parse(raw || "{}")
    if (!parsed || typeof parsed !== "object") return { connected: false }
    return parsed
  } catch (e) {
    return { connected: false }
  }
}

// Build a status object from the flat values map.
// supported flags are derived from whether the setting ID exists in the map.
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

// Collapse the CLI's stderr into one line the panel can show inside a row.
function elideError(text) {
  var value = String(text || "").replace(/\s+/g, " ").trim()
  return value.length > MAX_ERROR_CHARS ? value.substring(0, ELIDED_ERROR_CHARS) + "…" : value
}
