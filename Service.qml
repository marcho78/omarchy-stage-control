import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "Defaults.js" as Defaults
import "Settings.js" as Settings
import "Model.js" as Model

// Stage Control: macOS-style Mission Control for Omarchy.
//
// This service is the engine. It keeps Stage Control's input registered with Hyprland
// (hypr/stage.lua, run with `hyprctl eval`), listens for the events that input
// sends, follows trackpad swipes, reads Hyprland's state when Mission Control
// opens, and carries out what you do there: focusing windows, switching,
// adding, removing and reordering desktops, and moving windows between them.
// Overview.qml draws Mission Control on each display; Panel.qml is the
// settings window.
//
//   omarchy-shell stage-control toggle     Mission Control
//   omarchy-shell stage-control expose     App Exposé (the focused app's windows)
//   omarchy-shell stage-control settings   settings
Item {
  id: root

  // ---- host injection ----------------------------------------------------------

  property var shell: null
  property var manifest: null

  // The dev harness (dev/harness.qml) turns Hyprland registration off and puts
  // the overlays under the windows without taking the keyboard.
  property bool hyprIntegration: true
  property bool testMode: false

  readonly property string pluginId: "marcho78.stage-control"
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, ""))
  readonly property string home: Quickshell.env("HOME")

  // ---- settings ----------------------------------------------------------------
  //
  // Stage Control reads and writes no files. Like every Omarchy plugin it keeps its
  // settings inline on its own shell.json entry (only what differs from
  // Defaults.js), together with the desktops it keeps: the shell writes the
  // entry (updateEntryInline) and hands plugins a copy of the bar
  // configuration it lives in (barConfig), which is where Stage Control reads it back.

  readonly property var defaults: Defaults.DEFAULTS
  readonly property var schema: Defaults.SCHEMA
  property var user: ({})
  readonly property var settings: defaults ? Settings.merge(defaults, user, schema) : null
  readonly property color highlight: settings ? Settings.highlightColor(settings, String(Color.accent)) : Color.accent

  // Mission Control's text is set in the macOS system font when it's
  // installed, else the closest sans serif on the system.
  readonly property string uiFont: {
    var families = Qt.fontFamilies()
    var wanted = ["SF Pro Display", "SF Pro Text", "SF Pro", "Inter Display", "Inter", "Noto Sans", "Cantarell", "Liberation Sans"]
    for (var i = 0; i < wanted.length; i++) {
      if (families.indexOf(wanted[i]) >= 0) return wanted[i]
    }
    return "sans-serif"
  }

  // Stage Control's entry as the shell last saved it: settings, kept desktops
  // and desktop names.
  //
  // While the shell saves an entry it hands plugins a copy of its configuration
  // from just before the save, and nothing refreshes that copy afterwards. So a
  // copy that arrives during Stage Control's own save, or that still shows the entry as
  // it was before that save, is old news and must not undo it.
  property bool saving: false
  property string entryBeforeSave: ""

  function loadEntry() {
    if (saving || persistTimer.running) return
    var entry = Settings.entryInBar(shell ? shell.barConfig : null, pluginId)
    if (entryBeforeSave !== "" && JSON.stringify(entry) === entryBeforeSave) return
    entryBeforeSave = ""
    pinned = Model.cleanDesktops(entry.desktops)
    pinnedVersion++
    desktopNames = Model.cleanDesktopNames(entry.desktopNames)
    delete entry.desktops
    delete entry.desktopNames
    user = entry
  }

  onShellChanged: loadEntry()

  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function onBarConfigChanged() { root.loadEntry() }
  }

  function setSetting(key, value) {
    if (!defaults || defaults[key] === undefined) return
    var next = Settings.clone(user)
    next[key] = value
    user = Settings.overrides(defaults, Settings.merge(defaults, next, schema))
    persistTimer.restart()
  }

  function resetSettings() {
    user = ({})
    persistTimer.restart()
  }

  Timer {
    id: persistTimer
    interval: 300
    onTriggered: {
      if (!root.shell || typeof root.shell.updateEntryInline !== "function") return
      var entry = Settings.clone(root.user)
      if (Object.keys(root.pinned).length > 0) entry.desktops = Settings.clone(root.pinned)
      if (Object.keys(root.desktopNames).length > 0) entry.desktopNames = Settings.clone(root.desktopNames)
      root.entryBeforeSave = JSON.stringify(Settings.entryInBar(root.shell.barConfig, root.pluginId))
      root.saving = true
      try {
        root.shell.updateEntryInline(root.pluginId, entry)
      } finally {
        root.saving = false
      }
    }
  }

  // ---- Hyprland registration ----------------------------------------------------
  //
  // Gestures and shortcuts are registered at runtime; your Hyprland config is
  // never edited. A config reload clears them, so they're registered again on
  // every `configreloaded` event.

  property string hyprStatus: ""
  property var takenBinds: []
  property bool registering: false
  property bool registerAgain: false

  readonly property string registrationKey: settings ? JSON.stringify([
    settings.gestureFingers, settings.desktopSwipeFingers, settings.shortcuts,
    settings.missionControlKey, settings.appWindowsKey, settings.macShortcuts
  ]) : ""
  onRegistrationKeyChanged: scheduleRegister()

  function scheduleRegister() {
    if (hyprIntegration && settings) registerTimer.restart()
  }

  Timer {
    id: registerTimer
    // Long enough for a hot-reloaded predecessor's cleanup to land first.
    interval: 350
    onTriggered: root.register()
  }

  function register() {
    if (registering) {
      registerAgain = true
      return
    }
    registering = true
    bindsRun.start(["/usr/bin/hyprctl", "-j", "binds"])
  }

  Run {
    id: bindsRun
    maxBytes: 512 * 1024
    timeoutMs: 4000
    onFinished: function(ok, output) {
      var existing = []
      try { existing = JSON.parse(output) } catch (e) { existing = [] }
      var checked = Settings.checkBinds(Settings.wantedBinds(root.settings), existing)
      root.takenBinds = checked.taken
      var options = Settings.hyprOptions(root.settings, checked.free)
      registerRun.start(["/usr/bin/hyprctl", "eval", Settings.hyprRegistration(root.pluginDir + "/hypr/stage.lua", options)])
    }
  }

  Run {
    id: registerRun
    maxBytes: 16 * 1024
    timeoutMs: 4000
    onFinished: function(ok, output) {
      var text = String(output || "").trim()
      root.hyprStatus = ok && (text === "" || text === "ok") ? "ok" : (text || "Hyprland didn't answer")
      if (root.hyprStatus !== "ok") console.warn("Stage Control: registering with Hyprland:", root.hyprStatus)
      root.registering = false
      if (root.registerAgain) {
        root.registerAgain = false
        root.register()
      }
    }
  }

  // Take everything back out of Hyprland when the plugin is disabled or
  // reloaded. A reloaded copy registers again right after.
  Component.onDestruction: {
    if (hyprIntegration)
      Quickshell.execDetached(["/usr/bin/hyprctl", "eval",
        Settings.hyprRegistration(pluginDir + "/hypr/stage.lua", { fingers: 0, desktopSwipe: 0, binds: [] })])
  }

  // ---- Hyprland state ------------------------------------------------------------

  property var snap: null
  property var layers: ({})
  property var decor: ({ border: 0, bar: 0, rounding: 0 })
  property int snapVersion: 0
  property var snapWaiters: []
  property var laterWaiters: []
  property bool snapPending: false

  // A callback is answered by a read that starts after the call, never by one
  // already under way, which may predate what the caller just changed.
  function refresh(callback) {
    var started = snapRun.start(["/usr/bin/hyprctl", "-j", "--batch",
      "clients; monitors; workspaces; layers; getoption general:border_size; getoption plugin:hyprbars:bar_height; getoption decoration:rounding"])
    if (!started) snapPending = true
    if (typeof callback !== "function") return
    if (started) snapWaiters = snapWaiters.concat([callback])
    else laterWaiters = laterWaiters.concat([callback])
  }

  Run {
    id: snapRun
    maxBytes: 1024 * 1024
    timeoutMs: 3000
    onFinished: function(ok, output) {
      var good = false
      if (ok) {
        try {
          var parts = Model.splitJson(output)
          if (parts.length >= 3 && Array.isArray(parts[0]) && Array.isArray(parts[1]) && Array.isArray(parts[2])) {
            var rest = parts.slice(3)
            root.layers = rest.length && rest[0] && !Array.isArray(rest[0]) && rest[0].option === undefined ? rest.shift() : ({})
            root.decor = Model.decorFrom(rest)
            root.snap = Model.snapshot(parts[0], parts[1], parts[2])
            root.snapVersion++
            good = true
          }
        } catch (e) {
          console.warn("Stage Control: couldn't read Hyprland's state:", e)
        }
      }
      var waiters = root.snapWaiters
      root.snapWaiters = []
      waiters.forEach(function(callback) { callback(good) })
      // App Exposé ends when its app's last window closes.
      if (good && root.interactive && root.mode === "expose" && root.exposeClass
          && Model.appWindows(root.snap, root.exposeClass).length === 0
          && ((root.settings && root.settings.showMinimized === false) || Model.minimizedWindows(root.snap, root.exposeClass).length === 0))
        root.close({})
      if (root.snapPending) {
        root.snapPending = false
        var later = root.laterWaiters
        root.laterWaiters = []
        // Whether this starts the next read or one of the callbacks above
        // already did, that read began after these callers asked.
        root.refresh(null)
        root.snapWaiters = root.snapWaiters.concat(later)
      }
    }
  }

  // While Mission Control is open it follows what Hyprland does.
  Timer {
    id: followTimer
    interval: 60
    onTriggered: root.refresh(null)
  }

  readonly property var followedEvents: [
    "openwindow", "closewindow", "movewindowv2", "workspacev2", "focusedmonv2", "fullscreen",
    "changefloatingmode", "windowtitlev2", "createworkspacev2", "destroyworkspacev2",
    "moveworkspacev2", "activespecialv2", "pin", "monitoraddedv2", "monitorremovedv2"
  ]

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name
      if (name === "custom") {
        root.handleEvent(Settings.parseEvent(event.data))
      } else if (name === "configreloaded") {
        root.scheduleRegister()
      } else if (root.shown && root.followedEvents.indexOf(name) >= 0) {
        followTimer.restart()
      }
    }
  }

  // HyprlandToplevel for a window address; it carries the Wayland handle that
  // the live previews capture.
  function toplevelFor(address) {
    var key = String(address || "").replace(/^0x/, "")
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].address === key) return list[i]
    }
    return null
  }

  // ---- apps ----------------------------------------------------------------------

  property var appCache: ({})

  // A window class's name and icon. Web apps are matched to the entry that
  // opens their site; anything else by the names Model.appKeys lists.
  function appFor(cls) {
    var key = String(cls || "")
    if (appCache[key]) return appCache[key]
    var keys = Model.appKeys(key)
    var entry = webAppEntry(Model.webAppHost(key))
    for (var i = 0; !entry && i < keys.length; i++) entry = DesktopEntries.heuristicLookup(keys[i])
    var icon = ""
    if (entry && entry.icon) icon = Quickshell.iconPath(entry.icon, true)
    for (i = 0; !icon && i < keys.length; i++) icon = Quickshell.iconPath(keys[i].toLowerCase(), true)
    if (!icon) icon = Quickshell.iconPath("application-x-executable", true)
    var name = entry && entry.name ? entry.name : Model.appName(key)
    var app = { icon: icon || "", name: name }
    appCache[key] = app
    return app
  }

  // The installed web app whose entry opens `host`, if any.
  function webAppEntry(host) {
    if (!host) return null
    var list = DesktopEntries.applications.values
    for (var i = 0; i < list.length; i++) {
      if (list[i] && Model.launchedSite(list[i].execString) === host) return list[i]
    }
    return null
  }

  // ---- wallpaper -------------------------------------------------------------------
  //
  // Resolved the way Omarchy's background does it, so Mission Control shows the
  // very image the desktop has (straight from the shell's image cache).

  property string wallpaper: ""
  readonly property string wallpaperUrl: wallpaper ? Util.fileUrl(wallpaper) : ""

  Run {
    id: wallpaperRun
    maxBytes: 4 * 1024
    timeoutMs: 2000
    onFinished: function(ok, output) {
      // An absolute path of printable characters, or nothing.
      var path = String(output || "").trim()
      if (ok && /^\/[^\u0000-\u001f\u007f]{1,4000}$/.test(path)) root.wallpaper = path
    }
  }

  function refreshWallpaper() {
    wallpaperRun.start(["/usr/bin/readlink", "-f", home + "/.local/state/omarchy/current/background"])
  }

  // ---- desktops kept while empty ------------------------------------------------------
  //
  // Hyprland drops empty workspaces; macOS keeps desktops until you remove
  // them. Stage Control remembers which desktops each display has, by display name,
  // on its shell.json entry.

  property var pinned: ({})
  property int pinnedVersion: 0

  function savePinned(next) {
    pinned = Model.cleanDesktops(next)
    pinnedVersion++
    persistTimer.restart()
  }

  function desktopsFor(monitorName) {
    if (!snap) return []
    return Model.desktops(snap, monitorName, pinned[monitorName] || [])
  }

  function withPinned(monitorName, ids) {
    var next = Settings.clone(pinned)
    next[monitorName] = ids.slice().sort(function(a, b) { return a - b })
    return next
  }

  // ---- desktop names ------------------------------------------------------------------
  //
  // Names you give desktops, by desktop id, on the same shell.json entry. They
  // follow a desktop's windows when desktops are reordered or renumbered.
  // Hyprland's own workspace names aren't used: Hyprland forgets them whenever
  // an empty workspace goes away.

  property var desktopNames: ({})

  function saveNames(next) {
    desktopNames = Model.cleanDesktopNames(next)
    persistTimer.restart()
  }

  // An empty name goes back to the default ("Desktop 3").
  function renameDesktop(id, name) {
    if (!validId(id) || !snap) return
    var home = null
    snap.monitors.forEach(function(monitor) {
      if (!home && desktopsFor(monitor.name).some(function(d) { return d.id === id })) home = monitor.name
    })
    if (!home) return
    var next = Settings.clone(desktopNames)
    var clean = Model.cleanDesktopName(name)
    if (clean) next[String(id)] = clean
    else delete next[String(id)]
    saveNames(next)
    // A named desktop is kept, like one you add, even while it's empty.
    savePinned(withPinned(home, desktopsFor(home).map(function(d) { return d.id })))
  }

  // ---- actions ---------------------------------------------------------------------

  function validId(id) {
    return typeof id === "number" && isFinite(id) && id > 0 && id < 100000 && Math.round(id) === id
  }

  function focusWindow(address) {
    if (Model.isAddress(address)) Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  function focusDesktop(id) {
    if (validId(id)) Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })')
  }

  function closeWindow(address) {
    if (Model.isAddress(address)) Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + address + '" })')
    followTimer.restart()
  }

  // Changes that move windows run one at a time. One that comes while
  // another's moves are still running waits for them instead of being
  // dropped, and is then planned from a fresh read of Hyprland, since the
  // windows have moved.
  property var planQueue: []

  function whenPlansDone(action) {
    if (planRun.running || planQueue.length > 0) planQueue = planQueue.concat([action])
    else action()
  }

  function nextPlans() {
    while (planQueue.length > 0 && !planRun.running) {
      var action = planQueue[0]
      planQueue = planQueue.slice(1)
      action()
    }
  }

  Run {
    id: planRun
    maxBytes: 16 * 1024
    timeoutMs: 4000
    onFinished: root.refresh(function() { root.nextPlans() })
  }

  function runPlan(moves, focus, focusAddress) {
    var lua = Model.planLua(moves, focus, focusAddress)
    if (lua) planRun.start(["/usr/bin/hyprctl", "eval", lua])
    else refresh(null)
  }

  // A minimized window (Title Bars keeps them on special:minimized) comes back
  // to the desktop on screen, focused. One eval keeps the order.
  function restoreWindow(address, desktop) {
    if (!Model.isAddress(address) || !validId(desktop)) return
    whenPlansDone(function() { root.runPlan([{ address: address, to: desktop }], 0, address) })
  }

  function moveWindowToDesktop(address, id, monitorName) {
    if (!Model.isAddress(address) || !validId(id)) return
    whenPlansDone(function() {
      var ids = root.desktopsFor(monitorName).map(function(d) { return d.id })
      if (ids.indexOf(id) < 0) ids.push(id)
      root.savePinned(root.withPinned(monitorName, ids))
      root.runPlan([{ address: address, to: id }], 0)
    })
  }

  function addDesktop(monitorName) {
    if (!snap) return 0
    var id = Model.nextDesktopId(snap, pinned)
    var ids = desktopsFor(monitorName).map(function(d) { return d.id })
    ids.push(id)
    savePinned(withPinned(monitorName, ids))
    // A new desktop starts with the default name, whatever an old one there had.
    if (desktopNames[String(id)] !== undefined) {
      var names = Settings.clone(desktopNames)
      delete names[String(id)]
      saveNames(names)
    }
    return id
  }

  function moveWindowToNewDesktop(address, monitorName) {
    var id = addDesktop(monitorName)
    if (id) moveWindowToDesktop(address, id, monitorName)
  }

  function removeDesktop(monitorName, id) {
    whenPlansDone(function() {
      if (!root.snap) return
      var plan = Model.removalPlan(root.snap, monitorName, root.pinned, id, root.settings ? root.settings.renumberDesktops : true)
      if (!plan.ok) return
      root.savePinned(root.withPinned(monitorName, plan.pinned))
      root.saveNames(Model.carryNames(root.desktopNames, plan.carry))
      root.runPlan(plan.moves, plan.focus)
    })
  }

  function reorderDesktop(monitorName, fromId, toId) {
    whenPlansDone(function() {
      if (!root.snap) return
      var plan = Model.reorderPlan(root.snap, monitorName, root.pinned, fromId, toId)
      if (!plan.ok) return
      root.saveNames(Model.carryNames(root.desktopNames, plan.carry))
      root.runPlan(plan.moves, plan.focus)
    })
  }

  // Previous or next desktop on the focused display (macOS Ctrl+Left/Right).
  function stepDesktop(direction) {
    refresh(function(ok) {
      if (!ok || !root.snap) return
      var monitor = Model.focusedMonitor(root.snap)
      if (!monitor) return
      var list = root.desktopsFor(monitor.name).map(function(d) { return d.id })
      var index = list.indexOf(monitor.activeWorkspace)
      var next = list[index + direction]
      if (next !== undefined) root.focusDesktop(next)
    })
  }

  function openSettings(page) {
    if (shell && typeof shell.summon === "function")
      shell.summon(pluginId, JSON.stringify(page ? { page: String(page) } : {}))
  }

  function runCornerAction(action) {
    if (action === "missionControl") open("mission")
    else if (action === "appWindows") open("expose")
    else if (action === "launchpad") Quickshell.execDetached(["/usr/bin/omarchy", "menu", "toggle", "apps"])
    else if (action === "menu") Quickshell.execDetached(["/usr/bin/omarchy", "menu", "toggle"])
    else if (action === "lock") Quickshell.execDetached(["/usr/bin/omarchy", "system", "lock"])
    else if (action === "screensaver") Quickshell.execDetached(["/usr/bin/omarchy", "launch", "screensaver"])
  }

  // ---- opening and closing -----------------------------------------------------------
  //
  // progress runs from 0 (the desktop, every window where it really is) to 1
  // (Mission Control). Trackpad swipes set it directly; everything else
  // animates it.

  property string mode: ""            // "", "mission" or "expose"
  property string exposeClass: ""
  property real progress: 0
  property bool tracking: false       // following the fingers right now
  property bool closing: false
  property bool revealed: false       // captures are ready; draw the overlay
  property string exitAddress: ""     // window to zoom into on the way out
  property var readyScreens: ({})
  property int openSerial: 0
  readonly property bool shown: mode !== ""
  readonly property bool interactive: shown && revealed && !tracking && !closing
  readonly property real speedFactor: settings ? settings.speed / 100 : 1

  // Other plugins can follow Mission Control on Hyprland's event socket:
  // custom>>marcho78.stage-control|state|open and …|state|closed.
  onShownChanged: {
    if (hyprIntegration) Hyprland.dispatch('hl.dsp.event("' + Settings.EVENT_PREFIX + 'state|' + (shown ? "open" : "closed") + '")')
  }

  function open(which) {
    which = which === "expose" ? "expose" : "mission"
    if (shown && !closing) {
      if (mode === which) close({})
      else startMode(which, false)
      return
    }
    startMode(which, false)
  }

  // App Exposé for any app, by window class (`omarchy-shell stage-control exposeApp firefox`).
  function exposeApp(cls) {
    if (typeof cls !== "string" || cls === "" || cls.length > 128) return
    if (shown && !closing && mode === "expose" && exposeClass === cls) {
      close({})
      return
    }
    startMode("expose", false, cls)
  }

  // Shows the overlays for `which`; they capture every window and report
  // ready, then the opening animation starts (or the fingers take over).
  function startMode(which, byGesture, forcedClass) {
    progressAnim.stop()
    closing = false
    exitAddress = ""
    var serial = ++openSerial
    refreshWallpaper()
    refresh(function(ok) {
      // Closed (or reopened) again before Hyprland answered.
      if (serial !== root.openSerial) return
      if (!ok || !root.snap) {
        root.tracking = false
        return
      }
      if (which === "expose" && forcedClass) {
        if (Model.appWindows(root.snap, forcedClass).length === 0 && Model.minimizedWindows(root.snap, forcedClass).length === 0) return
        root.exposeClass = forcedClass
      } else if (which === "expose") {
        var active = Model.activeWindow(root.snap)
        if (!active || active.special) {
          if (!root.shown) {
            root.tracking = false
            root.swipeIntent = "ignore"
            root.progress = 0
          }
          return
        }
        root.exposeClass = active.cls
      }
      var wasShown = root.shown
      root.mode = which
      if (wasShown && root.revealed) {
        if (!root.tracking) root.animateTo(1)
        return
      }
      root.readyScreens = ({})
      root.revealed = false
      if (!byGesture) root.progress = 0
      revealTimer.restart()
    })
  }

  // Overlays call this once their previews have content.
  function markReady(screenName) {
    if (!shown || revealed) return
    var next = Settings.clone(readyScreens)
    next[screenName] = true
    readyScreens = next
    if (Object.keys(next).length >= expectedScreens()) reveal()
  }

  function expectedScreens() {
    return mode === "expose" ? 1 : Math.max(1, Quickshell.screens.length)
  }

  Timer {
    id: revealTimer
    // Don't wait forever on a window that won't give a frame.
    interval: 160
    onTriggered: root.reveal()
  }

  function reveal() {
    if (!shown || revealed) return
    revealTimer.stop()
    revealed = true
    if (!tracking && !closing) animateTo(1)
  }

  function close(options) {
    options = options || {}
    if (!shown) {
      // A swipe that let go before Hyprland answered: call off the opening.
      openSerial++
      tracking = false
      progress = 0
      return
    }
    tracking = false
    closing = true
    exitAddress = Model.isAddress(options.address) ? options.address : ""
    if (exitAddress) {
      if (!options.noFocus) focusWindow(exitAddress)
      animateTo(0)
    } else if (validId(options.desktop)) {
      // Switch first, then zoom into the new desktop's windows.
      focusDesktop(options.desktop)
      refresh(function() { root.animateTo(0) })
    } else {
      animateTo(0, options.velocity || 0)
    }
  }

  function finishClose() {
    progressAnim.stop()
    openSerial++
    mode = ""
    closing = false
    tracking = false
    revealed = false
    exitAddress = ""
    exposeClass = ""
    progress = 0
  }

  NumberAnimation {
    id: progressAnim
    target: root
    property: "progress"
    onFinished: {
      if (root.closing && root.progress <= 0.001) root.finishClose()
    }
  }

  function animateTo(target, velocity) {
    progressAnim.stop()
    var reduce = settings && settings.reduceMotion
    var distance = Math.abs(target - progress)
    if (distance < 0.001) {
      progress = target
      if (closing && target === 0) finishClose()
      return
    }
    var base = target > progress ? 460 : 380
    if (reduce) base = 220
    var duration = base * Math.max(0.35, distance) / speedFactor
    // A quick flick finishes quicker.
    if (velocity) duration = Math.min(duration, Math.max(140, distance / Math.max(0.0001, Math.abs(velocity)) * 1.6))
    progressAnim.from = progress
    progressAnim.to = target
    progressAnim.duration = Math.round(duration)
    progressAnim.easing.type = reduce ? Easing.InOutQuad : Easing.OutCubic
    progressAnim.start()
  }

  // ---- trackpad ----------------------------------------------------------------------

  readonly property real swipeDistance: 240
  property real swipeTravel: 0
  property string swipeIntent: ""     // "", "open", "close" or "ignore"
  property int swipeDirection: 0      // sign of a swipe toward "open": -1 up (Mission Control), +1 down (App Exposé)
  property real swipeOrigin: 0        // progress when the fingers took over
  property var swipeSamples: []
  property string lastGestureKey: ""

  function handleEvent(event) {
    if (!event) return
    if (event.type === "command") {
      if (event.command === "toggle") open("mission")
      else if (event.command === "expose") open("expose")
      else if (event.command === "desktop-prev") stepDesktop(-1)
      else if (event.command === "desktop-next") stepDesktop(1)
      return
    }
    // A second registration of the same gesture would send every step twice.
    var key = [event.phase, event.time, event.dx, event.dy].join(":")
    if (key === lastGestureKey) return
    lastGestureKey = key
    if (event.phase === "start") gestureStart(event)
    else if (event.phase === "update") gestureUpdate(event)
    else gestureFinish(event)
  }

  function gestureStart(event) {
    swipeTravel = 0
    swipeIntent = ""
    swipeSamples = []
    // Read Hyprland now so the overlay is ready by the time the fingers commit.
    if (!shown) refresh(null)
    gestureUpdate(event)
  }

  function gestureUpdate(event) {
    if (swipeIntent === "ignore") return
    swipeTravel += event.dy
    var samples = swipeSamples.slice(-5)
    samples.push({ dy: event.dy, time: event.time })
    swipeSamples = samples
    if (swipeIntent === "") decideIntent()
    if (swipeIntent === "open" || swipeIntent === "close")
      progress = Math.max(0, Math.min(1, swipeOrigin + swipeTravel * swipeDirection / swipeDistance))
  }

  function decideIntent() {
    if (Math.abs(swipeTravel) < 6) return
    var up = swipeTravel < 0
    if (!shown) {
      if (up) beginTracking("mission", -1, "open")
      else if (settings && settings.appExposeGesture) beginTracking("expose", 1, "open")
      else swipeIntent = "ignore"
      return
    }
    // Mission Control opens upward and App Exposé downward; while one is open
    // (or on its way in or out), the fingers take it over from where it is.
    var direction = mode === "expose" ? 1 : -1
    var towardOpen = (up ? -1 : 1) === direction
    beginTracking(mode, direction, towardOpen ? "open" : "close")
  }

  function beginTracking(which, direction, intent) {
    progressAnim.stop()
    var fresh = !shown
    swipeIntent = intent
    swipeDirection = direction
    tracking = true
    closing = false
    // Pick up from the current state, minus the travel so far.
    swipeOrigin = fresh ? 0 : progress - swipeTravel * direction / swipeDistance
    if (fresh) startMode(which, true)
    progress = Math.max(0, Math.min(1, swipeOrigin + swipeTravel * direction / swipeDistance))
  }

  // Speed toward "open" at the moment the fingers lifted, in distance units
  // per millisecond. Fingers that stopped before lifting have no speed.
  function swipeVelocity(liftTime) {
    var all = swipeSamples
    if (all.length < 2) return 0
    var end = liftTime > 0 ? liftTime : all[all.length - 1].time
    var samples = all.filter(function(sample) { return end - sample.time <= 90 })
    if (samples.length < 2) return 0
    var dt = Math.max(1, end - samples[0].time)
    var travel = 0
    for (var i = 1; i < samples.length; i++) travel += samples[i].dy
    return travel * swipeDirection / dt
  }

  function gestureFinish(event) {
    var intent = swipeIntent
    swipeIntent = ""
    if (!tracking) return
    tracking = false
    var velocity = swipeVelocity(event.time)
    var perUnit = velocity / swipeDistance
    // Where the fingers were heading decides, then how far they got: a third
    // of the way opens it, a third of the way back closes it.
    var threshold = intent === "close" ? 0.7 : 0.3
    var open = velocity > 0.35 ? true : velocity < -0.35 ? false : progress > threshold
    if (event.cancelled) open = progress > 0.5
    if (open) {
      if (revealed) animateTo(1, perUnit)
    } else {
      close({ velocity: perUnit })
    }
  }

  // ---- hot corners and overlays ----------------------------------------------------------

  // Each display's Overview, by display name (the dev harness grabs them).
  property var overviews: ({})

  function registerOverview(name, item) { overviews[name] = item }
  function unregisterOverview(name, item) { if (overviews[name] === item) delete overviews[name] }

  Variants {
    model: Quickshell.screens
    delegate: Overview {
      service: root
    }
  }

  Variants {
    model: root.testMode ? [] : Quickshell.screens
    delegate: HotCorners {
      service: root
    }
  }

  // ---- IPC --------------------------------------------------------------------------------

  IpcHandler {
    target: "stage-control"

    function toggle(): void { root.open("mission") }
    function show(): void { if (!root.shown || root.closing) root.open("mission") }
    function hide(): void { root.close({}) }
    function expose(): void { root.open("expose") }
    function exposeApp(appClass: string): void { root.exposeApp(appClass) }
    function settings(): void { root.openSettings("") }
    function desktopNext(): void { root.stepDesktop(1) }
    function desktopPrevious(): void { root.stepDesktop(-1) }

    // Desktop management on the focused display, for scripts and bindings.
    function addDesktop(): void {
      root.refresh(function(ok) {
        var monitor = ok && root.snap ? Model.focusedMonitor(root.snap) : null
        if (monitor) root.addDesktop(monitor.name)
      })
    }
    function removeDesktop(desktop: string): void {
      root.refresh(function(ok) {
        var monitor = ok && root.snap ? Model.focusedMonitor(root.snap) : null
        if (monitor) root.removeDesktop(monitor.name, Number(desktop))
      })
    }
    function moveWindow(address: string, desktop: string): void {
      root.refresh(function(ok) {
        var monitor = ok && root.snap ? Model.focusedMonitor(root.snap) : null
        if (monitor) root.moveWindowToDesktop(address, Number(desktop), monitor.name)
      })
    }
    // An empty name goes back to the default.
    function renameDesktop(desktop: string, name: string): void {
      root.refresh(function(ok) { if (ok) root.renameDesktop(Number(desktop), name) })
    }
    function status(): string {
      return JSON.stringify({
        mode: root.mode,
        progress: Math.round(root.progress * 1000) / 1000,
        hyprland: root.hyprStatus,
        takenShortcuts: root.takenBinds,
        desktops: root.pinned,
        desktopNames: root.desktopNames
      })
    }
  }

  // ---- startup ----------------------------------------------------------------------------

  Component.onCompleted: {
    refreshWallpaper()
    scheduleRegister()
  }
}
