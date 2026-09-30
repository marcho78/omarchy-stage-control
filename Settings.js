// Settings.js - Stage Control's settings: the defaults from Defaults.js with
// the user's overrides on top, validated against its SCHEMA, plus the options
// handed to hypr/stage.lua.
//
// Shared by Service.qml, Panel.qml and tests/settings.test.cjs, so keep it
// plain JavaScript with no QML or Node APIs.

// Canonical modifier order, and Hyprland's modmask bits for each.
var MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT"]
var MODMASK = { SHIFT: 1, CTRL: 4, ALT: 8, SUPER: 64 }
var MODIFIER_ALIASES = { CONTROL: "CTRL", META: "SUPER", WIN: "SUPER", LOGO: "SUPER", MOD4: "SUPER", MOD1: "ALT" }

// Every message hypr/stage.lua may send back. The Lua side checks the same list.
var EVENTS = ["toggle", "expose", "desktop-prev", "desktop-next"]

// macOS accent colors (Big Sur and later), used when highlight isn't "accent".
var HIGHLIGHTS = {
  blue: "#0a84ff",
  purple: "#bf5af2",
  pink: "#ff375f",
  red: "#ff453a",
  orange: "#ff9f0a",
  yellow: "#ffd60a",
  green: "#32d74b",
  graphite: "#98989d"
}

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

// "SUPER + alt + a" -> { mods: ["SUPER", "ALT"], key: "A", modmask: 72, text: "SUPER + ALT + A" }.
// "" -> { empty: true }. Anything that isn't a plain modifier chord -> null.
function parseShortcut(text) {
  if (typeof text !== "string") return null
  var trimmed = text.trim()
  if (trimmed === "") return { empty: true, mods: [], key: "", modmask: 0, text: "" }
  if (trimmed.length > 64) return null
  var parts = trimmed.split("+").map(function(part) { return part.trim() })
  if (parts.some(function(part) { return part === "" })) return null
  var key = parts.pop()
  if (!/^[A-Za-z0-9_]{1,32}$/.test(key)) return null
  var mods = []
  for (var i = 0; i < parts.length; i++) {
    var mod = parts[i].toUpperCase()
    if (MODIFIER_ALIASES[mod]) mod = MODIFIER_ALIASES[mod]
    if (MODIFIERS.indexOf(mod) < 0 || mods.indexOf(mod) >= 0) return null
    mods.push(mod)
  }
  mods.sort(function(a, b) { return MODIFIERS.indexOf(a) - MODIFIERS.indexOf(b) })
  // Hyprland matches key names case-insensitively; write them the way Omarchy
  // does (SUPER + TAB), except XF86 media keys, which read better as named.
  var keyName = /^xf86/i.test(key) ? "XF86" + key.slice(4) : key.toUpperCase()
  var modmask = 0
  mods.forEach(function(mod) { modmask |= MODMASK[mod] })
  return { empty: false, mods: mods, key: keyName, modmask: modmask, text: mods.concat([keyName]).join(" + ") }
}

function validValue(key, value, fallback, schema) {
  var types = (schema && schema.types) || {}
  var choices = (schema && schema.choices) || {}
  var ranges = (schema && schema.ranges) || {}
  var type = types[key] || typeof fallback

  if (type === "bool") return typeof value === "boolean" ? { ok: true, value: value } : { ok: false }
  if (type === "int") {
    if (typeof value !== "number" || !isFinite(value) || Math.floor(value) !== value) return { ok: false }
    if (choices[key] && choices[key].indexOf(value) < 0) return { ok: false }
    if (ranges[key]) value = Math.min(ranges[key][1], Math.max(ranges[key][0], value))
    return { ok: true, value: value }
  }
  if (type === "shortcut") {
    var shortcut = parseShortcut(value)
    return shortcut ? { ok: true, value: shortcut.text } : { ok: false }
  }
  if (typeof value !== "string" || value.length > 64) return { ok: false }
  if (key === "highlight" && /^#[0-9a-fA-F]{6}$/.test(value)) return { ok: true, value: value.toLowerCase() }
  if (choices[key] && choices[key].indexOf(value) < 0) return { ok: false }
  return { ok: true, value: value }
}

// Defaults with the user's overrides on top. Unknown keys and invalid values
// are dropped, so a hand-edited shell.json can never feed bad data onwards.
function merge(defaults, user, schema) {
  var settings = clone(defaults || {})
  user = isPlainObject(user) ? user : {}
  Object.keys(settings).forEach(function(key) {
    if (user[key] === undefined || user[key] === null) return
    var checked = validValue(key, user[key], settings[key], schema)
    if (checked.ok) settings[key] = checked.value
  })
  return settings
}

// Only what differs from the defaults, so plugin updates can improve them.
function overrides(defaults, settings) {
  var out = {}
  Object.keys(defaults || {}).forEach(function(key) {
    if (settings[key] === undefined) return
    if (JSON.stringify(settings[key]) !== JSON.stringify(defaults[key])) out[key] = clone(settings[key])
  })
  return out
}

// Stage Control's own entry, without its id, from the copy of the bar configuration
// the Omarchy shell hands plugins (its `barConfig`). With its bar icon, Stage Control's
// entry lives in bar.layout, where the shell's updateEntryInline() writes it.
function entryInBar(barConfig, pluginId) {
  var layout = isPlainObject(barConfig) && isPlainObject(barConfig.layout) ? barConfig.layout : {}
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = Array.isArray(layout[sections[s]]) ? layout[sections[s]] : []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (isPlainObject(entry) && entry.id === pluginId) {
        var copy = clone(entry)
        delete copy.id
        return copy
      }
    }
  }
  return {}
}

function highlightColor(settings, accent) {
  var choice = settings && settings.highlight
  if (typeof choice === "string" && /^#[0-9a-fA-F]{6}$/.test(choice)) return choice
  return HIGHLIGHTS[choice] || accent || HIGHLIGHTS.blue
}

// The keyboard shortcuts Stage Control wants, in order of importance.
function wantedBinds(settings) {
  var binds = []
  if (!settings || settings.shortcuts === false) return binds
  function add(keys, event, description) {
    var shortcut = parseShortcut(keys)
    if (!shortcut || shortcut.empty) return
    if (binds.some(function(bind) { return bind.modmask === shortcut.modmask && bind.key.toUpperCase() === shortcut.key.toUpperCase() })) return
    binds.push({ keys: shortcut.text, key: shortcut.key, modmask: shortcut.modmask, event: event, description: description })
  }
  add(settings.stageKey, "toggle", "Open the stage")
  add(settings.appWindowsKey, "expose", "Application windows")
  if (settings.macShortcuts) {
    add("CTRL + UP", "toggle", "Open the stage")
    add("CTRL + DOWN", "expose", "Application windows")
    add("CTRL + LEFT", "desktop-prev", "Move left a desktop")
    add("CTRL + RIGHT", "desktop-next", "Move right a desktop")
    add("XF86LaunchA", "toggle", "Open the stage")
  }
  return binds
}

// Suffix that marks Stage Control's own binds in `hyprctl binds`.
var BIND_SUFFIX = " (Stage Control)"

// Splits the wanted binds into those that are free and those some other bind
// already uses. hyprBinds is the parsed output of `hyprctl -j binds`. When
// that couldn't be read, no bind is known to be free, so none is: every one
// comes back taken, marked unknown, rather than possibly doubling one of yours.
function checkBinds(wanted, hyprBinds) {
  var taken = []
  var free = []
  if (!Array.isArray(hyprBinds)) {
    wanted.forEach(function(bind) {
      taken.push({ keys: bind.keys, event: bind.event, description: bind.description, usedBy: "", unknown: true })
    })
    return { free: free, taken: taken }
  }
  var existing = hyprBinds
  wanted.forEach(function(bind) {
    var clash = null
    for (var i = 0; i < existing.length; i++) {
      var other = existing[i]
      if (!other || other.mouse === true) continue
      if (String(other.submap || "") !== "") continue
      var description = String(other.description || "")
      if (description.length >= BIND_SUFFIX.length && description.slice(-BIND_SUFFIX.length) === BIND_SUFFIX) continue
      if (Number(other.modmask) === bind.modmask && String(other.key || "").toUpperCase() === bind.key.toUpperCase()) {
        clash = description || String(other.dispatcher || "another binding")
        break
      }
    }
    if (clash) taken.push({ keys: bind.keys, event: bind.event, description: bind.description, usedBy: clash })
    else free.push(bind)
  })
  return { free: free, taken: taken }
}

// Options for hypr/stage.lua. Everything in here is a validated number,
// boolean, or string from a fixed set, so it can be written out as Lua.
function hyprOptions(settings, freeBinds) {
  var fingers = settings && [3, 4, 5].indexOf(settings.gestureFingers) >= 0 ? settings.gestureFingers : 0
  var swipe = settings && [3, 4, 5].indexOf(settings.desktopSwipeFingers) >= 0 ? settings.desktopSwipeFingers : 0
  return {
    fingers: fingers,
    desktopSwipe: swipe,
    binds: (freeBinds || []).filter(function(bind) {
      return EVENTS.indexOf(bind.event) >= 0 && /^[A-Za-z0-9_ +]{1,64}$/.test(bind.keys)
    }).map(function(bind) {
      return { keys: bind.keys, event: bind.event, description: bind.description + BIND_SUFFIX }
    })
  }
}

// A JavaScript value as a Lua literal. Strings are limited to printable ASCII
// by the callers; anything else is escaped byte by byte.
function luaString(text) {
  var out = "\""
  var value = String(text)
  for (var i = 0; i < value.length; i++) {
    var c = value.charAt(i)
    var code = value.charCodeAt(i)
    if (c === "\\" || c === "\"") out += "\\" + c
    else if (code >= 32 && code < 127) out += c
    else if (code < 128) out += "\\" + ("00" + code).slice(-3)
    else {
      // UTF-8 encode anything else (only file paths can contain it).
      var bytes = unescape(encodeURIComponent(c + (code >= 0xd800 && code < 0xdc00 ? value.charAt(++i) : "")))
      for (var j = 0; j < bytes.length; j++) out += "\\" + ("00" + bytes.charCodeAt(j)).slice(-3)
    }
  }
  return out + "\""
}

function luaLiteral(value) {
  if (value === null || value === undefined) return "nil"
  if (typeof value === "boolean") return value ? "true" : "false"
  if (typeof value === "number") return isFinite(value) ? String(value) : "0"
  if (typeof value === "string") return luaString(value)
  if (Array.isArray(value)) return "{" + value.map(luaLiteral).join(", ") + "}"
  if (isPlainObject(value)) {
    return "{" + Object.keys(value).filter(function(key) {
      return /^[A-Za-z_][A-Za-z0-9_]*$/.test(key)
    }).map(function(key) {
      return key + " = " + luaLiteral(value[key])
    }).join(", ") + "}"
  }
  return "nil"
}

// The code `hyprctl eval` runs: load hypr/stage.lua from the plugin and
// register with the given options. hyprctl prints "ok", or "error: …" naming
// what didn't register (and fails).
function hyprRegistration(moduleFile, options) {
  return "return dofile(" + luaString(moduleFile) + ")(" + luaLiteral(options) + ")"
}

// Parses a custom Hyprland event sent by hypr/stage.lua, e.g.
// "marcho78.stage-control|g|update|0.00|-12.50|1016.00|4". Returns null for other events.
var EVENT_PREFIX = "marcho78.stage-control|"

function parseEvent(data) {
  var text = String(data || "")
  // Stage Control's own messages are short; anything long isn't one of them.
  if (text.length > 160 || text.indexOf(EVENT_PREFIX) !== 0) return null
  var parts = text.slice(EVENT_PREFIX.length).split("|")
  if (parts[0] === "g") {
    var phase = parts[1]
    if (phase === "start" || phase === "update") {
      return {
        type: "gesture", phase: phase,
        dx: Number(parts[2]) || 0, dy: Number(parts[3]) || 0,
        time: Number(parts[4]) || 0, fingers: Number(parts[5]) || 0
      }
    }
    if (phase === "finish") return { type: "gesture", phase: "finish", cancelled: parts[2] === "1", time: Number(parts[3]) || 0 }
    return null
  }
  if (EVENTS.indexOf(parts[0]) >= 0) return { type: "command", command: parts[0] }
  return null
}
