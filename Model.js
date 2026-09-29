// Model.js - what Hyprland has, in the shape the stage needs.
//
// The service reads one snapshot per opening with
//   hyprctl -j --batch "clients; monitors; workspaces"
// and everything below is derived from it: the desktops on each display, the
// windows to spread out, and the plans (lists of moves) for adding, removing
// and reordering desktops. Pure functions; tests/model.test.cjs.

// hyprctl --batch prints its JSON answers back to back; split them apart.
function splitJson(text) {
  var out = []
  var value = String(text || "")
  var depth = 0, start = -1, inString = false, escaped = false
  for (var i = 0; i < value.length; i++) {
    var c = value.charAt(i)
    if (inString) {
      if (escaped) escaped = false
      else if (c === "\\") escaped = true
      else if (c === "\"") inString = false
      continue
    }
    if (c === "\"") { inString = true; continue }
    if (c === "[" || c === "{") {
      if (depth === 0) start = i
      depth++
    } else if (c === "]" || c === "}") {
      depth--
      if (depth === 0 && start >= 0) {
        out.push(JSON.parse(value.slice(start, i + 1)))
        start = -1
      }
      if (depth < 0) throw new Error("unbalanced JSON")
    }
  }
  if (depth !== 0) throw new Error("truncated JSON")
  return out
}

function isAddress(value) {
  return typeof value === "string" && /^0x[0-9a-fA-F]{1,16}$/.test(value)
}

function int(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? Math.round(n) : fallback
}

function pair(value) {
  return Array.isArray(value) && value.length >= 2 ? [Number(value[0]) || 0, Number(value[1]) || 0] : [0, 0]
}

// A normalized snapshot: logical monitor sizes, window rects in global
// layout coordinates, and which workspace each monitor shows.
function snapshot(clients, monitors, workspaces) {
  var mons = (Array.isArray(monitors) ? monitors : []).filter(function(m) {
    return m && !m.disabled && typeof m.name === "string"
  }).map(function(m) {
    var scale = Number(m.scale) > 0 ? Number(m.scale) : 1
    var rotated = (int(m.transform, 0) % 2) === 1
    var width = Math.round((rotated ? m.height : m.width) / scale)
    var height = Math.round((rotated ? m.width : m.height) / scale)
    var reserved = Array.isArray(m.reserved) ? m.reserved : [0, 0, 0, 0]
    return {
      id: int(m.id, -1),
      name: m.name,
      x: int(m.x, 0), y: int(m.y, 0),
      w: width, h: height,
      scale: scale,
      focused: m.focused === true,
      activeWorkspace: m.activeWorkspace ? int(m.activeWorkspace.id, 0) : 0,
      specialWorkspace: m.specialWorkspace ? int(m.specialWorkspace.id, 0) : 0,
      specialName: m.specialWorkspace ? String(m.specialWorkspace.name || "") : "",
      reserved: { left: int(reserved[0], 0), top: int(reserved[1], 0), right: int(reserved[2], 0), bottom: int(reserved[3], 0) }
    }
  })

  var wss = (Array.isArray(workspaces) ? workspaces : []).filter(function(w) {
    return w && typeof w.id === "number"
  }).map(function(w) {
    return {
      id: w.id,
      name: String(w.name || w.id),
      monitor: String(w.monitor || ""),
      monitorId: int(w.monitorID, -1),
      windows: int(w.windows, 0),
      hasFullscreen: w.hasfullscreen === true,
      special: w.id < 0
    }
  })

  var wins = (Array.isArray(clients) ? clients : []).filter(function(c) {
    return c && isAddress(c.address) && c.mapped !== false && c.workspace && typeof c.workspace.id === "number"
  }).map(function(c) {
    var at = pair(c.at)
    var size = pair(c.size)
    var wsName = String(c.workspace.name || "")
    return {
      address: c.address,
      cls: String(c.class || c.initialClass || ""),
      title: String(c.title || c.initialTitle || ""),
      workspace: c.workspace.id,
      workspaceName: wsName,
      special: c.workspace.id < 0 || wsName.indexOf("special:") === 0,
      monitor: int(c.monitor, -1),
      x: at[0], y: at[1], w: Math.max(1, size[0]), h: Math.max(1, size[1]),
      floating: c.floating === true,
      fullscreen: int(c.fullscreen, 0),
      pinned: c.pinned === true,
      hidden: c.hidden === true,
      focus: int(c.focusHistoryID, 9999),
      xwayland: c.xwayland === true
    }
  })

  return { monitors: mons, workspaces: wss, windows: wins }
}

// Layer-shell surfaces above the windows (bar, dock, notifications) on one
// monitor, in monitor coordinates, from `hyprctl -j layers`. Stage Control's own
// surfaces are left out.
function surfaces(layers, monitor) {
  var out = []
  if (!layers || typeof layers !== "object" || !monitor) return out
  var entry = layers[monitor.name]
  var levels = entry && entry.levels ? entry.levels : {}
  ;["2", "3"].forEach(function(level) {
    ;(Array.isArray(levels[level]) ? levels[level] : []).forEach(function(surface) {
      var name = String(surface && surface.namespace || "")
      if (name.indexOf("marcho78-stage-control") === 0) return
      var w = int(surface.w, 0), h = int(surface.h, 0)
      if (w <= 0 || h <= 0) return
      out.push({ namespace: name, level: Number(level), x: int(surface.x, 0) - monitor.x, y: int(surface.y, 0) - monitor.y, w: w, h: h })
    })
  })
  return out
}

// Border, title bar (hyprbars, from the Title Bars plugin) and corner rounding,
// from the getoption answers in the same batch. Missing options count as 0.
function decorFrom(parts) {
  var decor = { border: 0, bar: 0, rounding: 0 }
  ;(parts || []).forEach(function(part) {
    if (!part || typeof part !== "object" || Array.isArray(part)) return
    var value = Math.max(0, Math.min(200, int(part.int, 0)))
    if (part.option === "general:border_size") decor.border = value
    else if (part.option === "plugin:hyprbars:bar_height") decor.bar = value
    else if (part.option === "decoration:rounding") decor.rounding = value
  })
  return decor
}

function monitorByName(snap, name) {
  for (var i = 0; i < snap.monitors.length; i++) if (snap.monitors[i].name === name) return snap.monitors[i]
  return null
}

function monitorById(snap, id) {
  for (var i = 0; i < snap.monitors.length; i++) if (snap.monitors[i].id === id) return snap.monitors[i]
  return null
}

function focusedMonitor(snap) {
  for (var i = 0; i < snap.monitors.length; i++) if (snap.monitors[i].focused) return snap.monitors[i]
  return snap.monitors.length ? snap.monitors[0] : null
}

// The focused window: the one Hyprland focused most recently.
function activeWindow(snap) {
  var best = null
  snap.windows.forEach(function(w) {
    if (!w.hidden && (best === null || w.focus < best.focus)) best = w
  })
  return best
}

// Windows visible on a monitor right now, front to back: its active workspace,
// its open special workspace, and pinned windows.
function visibleWindows(snap, monitor) {
  if (!monitor) return []
  return snap.windows.filter(function(w) {
    if (w.hidden || w.monitor !== monitor.id) return false
    if (w.pinned) return true
    if (w.workspace === monitor.activeWorkspace) return true
    return monitor.specialWorkspace !== 0 && w.workspace === monitor.specialWorkspace
  }).sort(function(a, b) { return a.focus - b.focus })
}

// Window rect relative to the monitor's top-left corner.
function localRect(w, monitor) {
  return { x: w.x - monitor.x, y: w.y - monitor.y, w: w.w, h: w.h }
}

// The regular (non-special) desktops on a monitor: every workspace Hyprland has
// there, plus desktops Stage Control keeps even when empty (`pinned`).
function desktops(snap, monitorName, pinned) {
  var monitor = monitorByName(snap, monitorName)
  var ids = {}
  snap.workspaces.forEach(function(ws) {
    if (!ws.special && ws.id > 0 && ws.monitor === monitorName) ids[ws.id] = true
  })
  ;(Array.isArray(pinned) ? pinned : []).forEach(function(id) {
    // A pinned desktop that Hyprland has put on another monitor belongs there.
    var elsewhere = snap.workspaces.some(function(ws) { return ws.id === id && ws.monitor !== monitorName })
    if (int(id, 0) > 0 && !elsewhere) ids[int(id, 0)] = true
  })
  if (monitor && monitor.activeWorkspace > 0) ids[monitor.activeWorkspace] = true
  return Object.keys(ids).map(Number).sort(function(a, b) { return a - b }).map(function(id) {
    var ws = null
    for (var i = 0; i < snap.workspaces.length; i++) if (snap.workspaces[i].id === id) ws = snap.workspaces[i]
    var windows = snap.windows.filter(function(w) { return w.workspace === id && !w.hidden })
    var fullscreen = null
    windows.forEach(function(w) { if (w.fullscreen === 2 && !fullscreen) fullscreen = w })
    return {
      id: id,
      name: ws ? ws.name : String(id),
      active: !!monitor && monitor.activeWorkspace === id,
      windows: windows.map(function(w) { return w.address }),
      fullscreenClass: fullscreen ? fullscreen.cls : "",
      fullscreenTitle: fullscreen ? fullscreen.title : ""
    }
  })
}

// Every desktop id in use on any monitor.
function usedIds(snap, pinnedByMonitor) {
  var used = {}
  snap.workspaces.forEach(function(ws) { if (!ws.special && ws.id > 0) used[ws.id] = true })
  Object.keys(pinnedByMonitor || {}).forEach(function(name) {
    ;(pinnedByMonitor[name] || []).forEach(function(id) { if (int(id, 0) > 0) used[int(id, 0)] = true })
  })
  return used
}

// The desktops Stage Control keeps per display, as stored on its shell.json entry:
// { "<display name>": [desktop ids] }. Anything else is dropped.
function cleanDesktops(value) {
  var clean = {}
  if (!value || typeof value !== "object" || Array.isArray(value)) return clean
  Object.keys(value).slice(0, 16).forEach(function(name) {
    if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(name) || !Array.isArray(value[name])) return
    var seen = {}
    clean[name] = value[name].filter(function(id) {
      var ok = typeof id === "number" && isFinite(id) && id > 0 && id < 100000 && Math.round(id) === id && !seen[id]
      if (ok) seen[id] = true
      return ok
    }).slice(0, 64)
  })
  return clean
}

// A desktop's name as typed: control characters and line breaks dropped,
// spaces collapsed, at most 32 characters. "" means the default name.
var nameJunkRe = /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g
var spacesRe = /\s+/g

function cleanDesktopName(value) {
  if (typeof value !== "string") return ""
  var text = value.replace(nameJunkRe, "").replace(spacesRe, " ").trim()
  return Array.from(text).slice(0, 32).join("").trim()
}

// Desktop names as stored on the shell.json entry: { "<desktop id>": "name" }.
// Ids are Hyprland's, which are unique across displays.
function cleanDesktopNames(value) {
  var clean = {}
  if (!value || typeof value !== "object" || Array.isArray(value)) return clean
  Object.keys(value).slice(0, 128).forEach(function(key) {
    if (!/^[1-9][0-9]{0,4}$/.test(key)) return
    var name = cleanDesktopName(value[key])
    if (name) clean[key] = name
  })
  return clean
}

// Names after a plan moves desktops' contents around: a desktop in `carry`
// hands its name to carry[id], or loses it where that is 0 (removed). Names of
// desktops the plan doesn't touch stay.
function carryNames(names, carry) {
  var next = {}
  Object.keys(names || {}).forEach(function(key) {
    if (carry[key] === undefined) next[key] = names[key]
  })
  Object.keys(carry || {}).forEach(function(key) {
    if (names[key] && carry[key] > 0) next[String(carry[key])] = names[key]
  })
  return next
}

// macOS adds a desktop at the end of the row: one past the highest in use.
function nextDesktopId(snap, pinnedByMonitor) {
  var used = usedIds(snap, pinnedByMonitor)
  var max = 0
  Object.keys(used).forEach(function(id) { max = Math.max(max, Number(id)) })
  return max + 1
}

// Ids that desktops on other monitors use (existing or pinned there).
function ownedElsewhere(snap, monitorName, pinnedByMonitor) {
  var owned = {}
  snap.workspaces.forEach(function(ws) {
    if (!ws.special && ws.id > 0 && ws.monitor !== monitorName) owned[ws.id] = true
  })
  Object.keys(pinnedByMonitor || {}).forEach(function(name) {
    if (name === monitorName) return
    ;(pinnedByMonitor[name] || []).forEach(function(other) { if (int(other, 0) > 0) owned[int(other, 0)] = true })
  })
  return owned
}

// Every window on one of `ids` that must end up somewhere else: `destination`
// maps each desktop id to the id its windows should be on afterwards.
function movesFor(snap, ids, destination) {
  var moves = []
  snap.windows.forEach(function(w) {
    if (w.pinned || ids.indexOf(w.workspace) < 0) return
    var to = destination(w.workspace)
    if (to !== w.workspace) moves.push({ address: w.address, to: to })
  })
  return moves
}

// What removing desktop `id` from a monitor takes: its windows move to the
// desktop before it (or after it, for the first), and the display switches
// there if it was showing `id`. With `renumber`, the desktops right after it
// shift down to close the gap, so desktop N stays workspace N (Super+N).
// Every window moves once, straight to where it ends up.
// Returns { ok, reason, moves: [{ address, to }], focus: id|0, pinned: [ids],
// carry: { id: new id, or 0 for the removed one } } (see carryNames).
function removalPlan(snap, monitorName, pinnedByMonitor, id, renumber) {
  var pinnedHere = (pinnedByMonitor && pinnedByMonitor[monitorName]) || []
  var list = desktops(snap, monitorName, pinnedHere).map(function(d) { return d.id })
  var index = list.indexOf(id)
  if (index < 0) return { ok: false, reason: "no such desktop" }
  if (list.length <= 1) return { ok: false, reason: "the last desktop can't be removed" }
  var monitor = monitorByName(snap, monitorName)
  var target = index > 0 ? list[index - 1] : list[index + 1]
  var remaining = list.filter(function(other) { return other !== id })

  // Close the gap the removal leaves: the desktops right after it, as long
  // as they run on without a gap of their own, each move down one. Desktops
  // further out (say 8 and 9, which window rules may target) stay put.
  var shift = {}
  if (renumber) {
    var owned = ownedElsewhere(snap, monitorName, pinnedByMonitor)
    for (var next = id + 1; remaining.indexOf(next) >= 0 && !owned[next - 1]; next++) shift[next] = next - 1
  }
  function renamed(other) { return shift[other] !== undefined ? shift[other] : other }

  var moves = movesFor(snap, list, function(from) { return renamed(from === id ? target : from) })
  var focus = 0
  if (monitor) {
    if (monitor.activeWorkspace === id) focus = renamed(target)
    else if (shift[monitor.activeWorkspace] !== undefined) focus = shift[monitor.activeWorkspace]
  }
  var carry = {}
  remaining.forEach(function(other) { carry[other] = renamed(other) })
  carry[id] = 0
  return { ok: true, moves: moves, focus: focus, pinned: remaining.map(renamed), carry: carry }
}

// Dragging a desktop in the Spaces bar to another desktop's place, as on
// macOS: the dragged desktop takes that position and the ones in between
// shift over by one. Desktop ids stay put; their windows move, and so do their
// names (carry, as in removalPlan).
// Returns { ok, moves, focus, carry }.
function reorderPlan(snap, monitorName, pinnedByMonitor, fromId, toId) {
  var pinnedHere = (pinnedByMonitor && pinnedByMonitor[monitorName]) || []
  var list = desktops(snap, monitorName, pinnedHere).map(function(d) { return d.id })
  var from = list.indexOf(fromId)
  var to = list.indexOf(toId)
  if (from < 0 || to < 0 || from === to) return { ok: false, moves: [], focus: 0 }
  var order = list.slice()
  order.splice(from, 1)
  order.splice(to, 0, fromId)
  // order[p] is the desktop whose windows now belong at list[p].
  var destinationOf = {}
  order.forEach(function(content, position) { destinationOf[content] = list[position] })
  var moves = movesFor(snap, list, function(content) { return destinationOf[content] })
  var monitor = monitorByName(snap, monitorName)
  var focus = 0
  if (monitor && destinationOf[monitor.activeWorkspace] !== undefined
      && destinationOf[monitor.activeWorkspace] !== monitor.activeWorkspace)
    focus = destinationOf[monitor.activeWorkspace]
  return { ok: true, moves: moves, focus: focus, carry: destinationOf }
}

// Lua for hyprctl eval that performs moves in order, then focuses a
// workspace or a window. Every value is validated here; nothing else reaches
// the code.
function planLua(moves, focus, focusAddress) {
  var lines = []
  ;(moves || []).forEach(function(move) {
    var to = move.to
    if (!isAddress(move.address)) return
    if (typeof to !== "number" || !isFinite(to) || Math.round(to) !== to || to <= 0 || to >= 100000) return
    lines.push("hl.dispatch(hl.dsp.window.move({ window = \"address:" + move.address + "\", workspace = \"" + to + "\", follow = false }))")
  })
  if (typeof focus === "number" && focus > 0 && focus < 100000 && Math.round(focus) === focus)
    lines.push("hl.dispatch(hl.dsp.focus({ workspace = \"" + focus + "\" }))")
  if (isAddress(focusAddress))
    lines.push("hl.dispatch(hl.dsp.focus({ window = \"address:" + focusAddress + "\" }))")
  return lines.join("\n")
}

// ---- which app a window belongs to ---------------------------------------------
// A window class doesn't always name its desktop entry. LocalSend's is
// org.localsend.localsend_app for localsend.desktop, and an Omarchy web app is
// a Chromium window with a class like chrome-app.hey.com__-Default whose entry
// runs "omarchy-launch-webapp https://..." (or a handler, for HEY and Zoom).
// The expressions live at module level so lookups don't allocate them.
var webAppClassRe = /^(?:chrome|chromium|brave|msedge|vivaldi|google-chrome)-([^_]+)__/i
var launchWebappRe = /omarchy-launch-webapp\s+["']?([^\s"']+)/
var appFlagRe = /--app=["']?([^\s"']+)/
var urlHostRe = /^[a-z][a-z0-9+.-]*:\/\/([^\/:?#]+)/i
var wwwRe = /^www\./i
var genericPartRe = /^(app|client|desktop|gui|ui)$/i
var genericSuffixRe = /[-_](app|client|desktop|gui|bin)$/i
var secondLevelRe = /^(co|com|net|org|gov|edu|ac)$/

// The site a web app window shows: "app.hey.com" for chrome-app.hey.com__-Default,
// "" for any other window (an extension's class has no "__").
function webAppHost(cls) {
  var match = String(cls || "").match(webAppClassRe)
  return match ? match[1].toLowerCase().replace(wwwRe, "") : ""
}

// The site a desktop entry's Exec line opens as a web app, or "".
function launchedSite(exec) {
  var text = String(exec || "")
  var match = text.match(launchWebappRe) || text.match(appFlagRe)
  var url = match ? match[1].match(urlHostRe) : null
  return url ? url[1].toLowerCase().replace(wwwRe, "") : ""
}

// A site's own name within its host: "hey" for app.hey.com, "bbc" for bbc.co.uk.
function siteName(host) {
  var labels = String(host || "").split(".")
  labels.pop()
  while (labels.length > 1 && secondLevelRe.test(labels[labels.length - 1])) labels.pop()
  return labels.length ? labels[labels.length - 1] : ""
}

// Names to look a window class up by, best first: the class itself; for a web
// app, its site's name; otherwise, for a reverse-DNS class, its app part, and
// the name without a generic suffix like "_app".
function appKeys(cls) {
  var key = String(cls || "")
  if (!key) return []
  var keys = [key]
  function add(name) { if (name && keys.indexOf(name) === -1) keys.push(name) }
  var host = webAppHost(key)
  if (host) {
    add(siteName(host))
    return keys
  }
  var parts = key.split(".").filter(function(part) { return part !== "" })
  var last = key
  if (parts.length >= 3) {
    last = parts[parts.length - 1]
    if (genericPartRe.test(last)) last = parts[parts.length - 2]
    add(last)
  }
  add(last.replace(genericSuffixRe, ""))
  return keys
}

// A readable name for an app with no desktop entry, from its window class:
// "org.gnome.Nautilus" -> "Nautilus", "herdr-gui" -> "Herdr Gui", and a web
// app's site.
function appName(cls) {
  var text = String(cls || "")
  var host = webAppHost(text)
  if (host) return host
  var last = text.split(".").filter(function(part) { return part !== "" }).pop() || text
  var words = last.split(/[-_ ]+/).filter(function(word) { return word !== "" })
  if (words.length === 0) return "Window"
  return words.map(function(word) { return word.charAt(0).toUpperCase() + word.slice(1) }).join(" ")
}

// Minimized windows (Title Bars keeps them on special:minimized).
function minimizedWindows(snap, cls) {
  return snap.windows.filter(function(w) {
    return w.workspaceName === "special:minimized" && (!cls || w.cls === cls)
  })
}

// Windows App Exposé shows for an app: on regular desktops, any monitor.
function appWindows(snap, cls) {
  return snap.windows.filter(function(w) {
    return !w.special && !w.hidden && w.cls === cls
  }).sort(function(a, b) { return a.focus - b.focus })
}
