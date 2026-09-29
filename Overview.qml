import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import "Layout.js" as Layout
import "Model.js" as Model

// The stage on one display: a full-screen layer over everything. At
// progress 0 it looks exactly like the desktop (the wallpaper, every window
// where it is, the bar); as progress goes to 1 the windows fly into the
// spread, the wallpaper blurs and dims, and the Spaces bar slides in.
PanelWindow {
  id: win

  required property var modelData       // the ShellScreen
  property var service: null

  screen: modelData
  readonly property string screenName: modelData ? modelData.name : ""
  readonly property var snap: service ? service.snap : null
  readonly property var monitor: snap ? Model.monitorByName(snap, screenName) : null
  readonly property bool showsHere: !!service && service.shown && !!monitor
    && (service.mode === "mission" || monitor.focused)
  readonly property real p: service ? service.progress : 0
  readonly property var settings: service && service.settings ? service.settings : ({})
  readonly property bool reduceMotion: settings.reduceMotion === true
  readonly property real e: reduceMotion ? 1 : p
  readonly property bool mission: !!service && service.mode === "mission"

  readonly property string glassStyle: settings.glass || "liquid"
  readonly property string windowTitles: settings.windowTitles || "hover"
  readonly property bool showIcons: settings.appIcons !== false
  readonly property bool showCloseButtons: settings.closeButtons !== false
  readonly property bool grouped: mission && settings.groupByApp === true
  readonly property color highlight: service ? service.highlight : "#0a84ff"
  readonly property string uiFont: service ? service.uiFont : ""
  readonly property real windowRounding: service ? service.decor.rounding : 0
  readonly property alias stage: stage
  readonly property alias spacesBar: spacesBar
  readonly property alias screenCapture: screenGhost
  readonly property alias glassBackdrop: glassBackdrop

  visible: showsHere
  color: "transparent"
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "marcho78-stage-control"
  WlrLayershell.layer: service && service.testMode ? WlrLayer.Background : WlrLayer.Overlay
  WlrLayershell.keyboardFocus: showsHere && !!service && !service.testMode && monitor.focused
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  function smooth(edge0, edge1, x) {
    var t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
  }

  Component.onCompleted: if (service) service.registerOverview(screenName, win)
  Component.onDestruction: if (service) service.unregisterOverview(screenName, win)

  // ---- model ----------------------------------------------------------------------

  property var tileIds: []
  property var tileData: ({})
  property var groups: []
  property var placed: ({})
  property var windowsByAddress: ({})
  property var desktopIds: []
  property var desktopData: ({})
  property var minimizedIds: []
  property string hoverAddress: ""
  property string selectedAddress: ""
  property bool forceExpanded: false

  function windowFor(address) {
    return windowsByAddress[address] || null
  }

  readonly property real barSpace: mission ? spacesBar.reservedHeight : 0
  onBarSpaceChanged: rebuild()
  onWidthChanged: rebuild()
  onHeightChanged: rebuild()
  onShowsHereChanged: {
    hoverAddress = ""
    selectedAddress = ""
    cancelDrag()
    spacesBar.commitRename()
    rebuild()
  }

  Connections {
    target: win.service
    function onSnapVersionChanged() { win.rebuild() }
    function onModeChanged() { win.rebuild() }
    function onExposeClassChanged() { win.rebuild() }
    function onPinnedVersionChanged() { win.rebuildDesktops() }
    function onSettingsChanged() { win.rebuild() }
  }

  function rebuildDesktops() {
    if (!showsHere || !service) {
      desktopIds = []
      desktopData = ({})
      return
    }
    var list = service.desktopsFor(screenName)
    var data = {}
    list.forEach(function(desktop) { data[desktop.id] = desktop })
    desktopIds = list.map(function(desktop) { return desktop.id })
    desktopData = data
  }

  function rebuild() {
    if (!showsHere || !snap || !monitor || width <= 0 || height <= 0) {
      tileIds = []
      tileData = ({})
      groups = []
      placed = ({})
      minimizedIds = []
      rebuildDesktops()
      return
    }
    var byAddress = {}
    snap.windows.forEach(function(w) { byAddress[w.address] = w })
    windowsByAddress = byAddress

    var expose = service.mode === "expose"
    var windows = expose ? Model.appWindows(snap, service.exposeClass) : Model.visibleWindows(snap, monitor)
    var minimized = expose && settings.showMinimized !== false ? Model.minimizedWindows(snap, service.exposeClass) : []

    var side = Math.round(Math.max(40, width * 0.045))
    var top = expose ? 96 : barSpace + 26
    var bottom = minimized.length ? Math.round(height * 0.2) + 40 : 64
    var area = { x: side, y: top, w: Math.max(100, width - side * 2), h: Math.max(100, height - top - bottom) }

    var items = windows.map(function(w) {
      var home = Model.monitorById(snap, w.monitor) || monitor
      return { id: w.address, x: w.x - home.x, y: w.y - home.y, w: w.w, h: w.h, group: w.cls }
    })
    // Titles shown on every window hang below it, so rows leave them room:
    // WindowTile's 26px pill, under the app icon (at most 44px, half of it
    // below the edge) when icons are on.
    var titleSpace = windowTitles === "always" ? (showIcons ? 22 + 6 : 10) + 26 : 0
    var result = Layout.spread(items, area, { gap: Math.round(Math.max(20, width * 0.022)), maxScale: 0.84, groupByApp: grouped, labelSpace: 46, titleSpace: titleSpace })

    var minimizedArea = { x: side, y: height - Math.round(height * 0.2) - 24, w: width - side * 2, h: Math.round(height * 0.2) }
    var minimizedResult = minimized.length
      ? Layout.spread(minimized.map(function(w) { return { id: w.address, x: w.x, y: w.y, w: w.w, h: w.h } }), minimizedArea, { gap: 20, maxScale: 0.3 })
      : { windows: {} }

    var data = {}
    var ids = []
    var rects = {}
    windows.forEach(function(w, index) {
      var to = result.windows[w.address]
      if (!to) return
      var onScreen = w.monitor === monitor.id && (w.pinned || w.workspace === monitor.activeWorkspace
        || (monitor.specialWorkspace !== 0 && w.workspace === monitor.specialWorkspace))
      var from = onScreen ? Model.localRect(w, monitor)
        : { x: to.x + to.w * 0.04, y: to.y + to.h * 0.04 + 30, w: to.w * 0.92, h: to.h * 0.92 }
      var app = service.appFor(w.cls)
      data[w.address] = {
        address: w.address, title: w.title, cls: w.cls, icon: app.icon, appName: app.name,
        from: from, to: to, onScreen: onScreen, minimized: false, workspace: w.workspace,
        z: (w.floating ? 200 : 0) + (windows.length - index)
      }
      ids.push(w.address)
      rects[w.address] = to
    })
    var minIds = []
    minimized.forEach(function(w) {
      var to = minimizedResult.windows[w.address]
      if (!to) return
      var app = service.appFor(w.cls)
      data[w.address] = {
        address: w.address, title: w.title, cls: w.cls, icon: app.icon, appName: app.name,
        from: { x: to.x, y: to.y + 60, w: to.w, h: to.h }, to: to, onScreen: false, minimized: true,
        workspace: w.workspace, z: 0
      }
      ids.push(w.address)
      minIds.push(w.address)
      rects[w.address] = to
    })

    // A window's title bar and border can come from the screen capture only
    // if no window above it covers them.
    var d = service.decor
    function decorated(rect) {
      return { x: rect.x - d.border, y: rect.y - d.border - d.bar, w: rect.w + d.border * 2, h: rect.h + d.border * 2 + d.bar }
    }
    function intersects(a, b) {
      return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
    }
    ids.forEach(function(address) {
      var info = data[address]
      if (!info.onScreen) return
      var mine = decorated(info.from)
      info.ghost = !ids.some(function(other) {
        var above = data[other]
        return other !== address && above.onScreen && above.z > info.z && intersects(mine, decorated(above.from))
      })
    })

    groups = result.groups.map(function(group) {
      var app = service.appFor(group.key)
      return { key: group.key, x: group.x, y: group.y, w: group.w, h: group.h, icon: app.icon, name: app.name }
    })
    tileData = data
    tileIds = ids
    placed = rects
    minimizedIds = minIds
    if (selectedAddress && !data[selectedAddress]) selectedAddress = ""
    if (hoverAddress && !data[hoverAddress]) hoverAddress = ""
    rebuildDesktops()
  }

  // ---- tiles ------------------------------------------------------------------------

  property var tileItems: ({})

  // Where each on-screen window was when the screen was captured. Its title
  // bar and border only come from the capture while it is still there.
  property var ghostRects: ({})

  Connections {
    target: win.service
    function onRevealedChanged() {
      if (!win.service.revealed) return
      var rects = {}
      for (var address in win.tileData) {
        var info = win.tileData[address]
        if (info.onScreen) rects[address] = info.from
      }
      win.ghostRects = rects
    }
  }

  function registerTile(address, item) { tileItems[address] = item }
  function unregisterTile(address, item) { if (tileItems[address] === item) delete tileItems[address] }

  // Ready to show once every preview has a frame (the service stops waiting
  // after a moment either way).
  Timer {
    interval: 16
    repeat: true
    running: win.showsHere && !!win.service && !win.service.revealed
    onTriggered: {
      if (!win.snap) return
      for (var i = 0; i < win.tileIds.length; i++) {
        var item = win.tileItems[win.tileIds[i]]
        if (!item || !item.hasContent) return
      }
      if (!screenGhost.hasContent) return
      if (wallpaper.status === Image.Loading) return
      win.service.markReady(win.screenName)
    }
  }

  function activate(address) {
    var info = tileData[address]
    if (!info || !service.interactive) return
    if (info.minimized) {
      service.restoreWindow(address, monitor.activeWorkspace)
      service.close({ address: address, noFocus: true })
    } else {
      service.close({ address: address })
    }
  }

  // how: "button" (the ×), "middle" (middle-click) or "key" (Ctrl+W).
  function closeWindow(address, how) {
    if (how === "middle" && settings.middleClickClose === false) return
    if (how === "button" && settings.closeButtons === false) return
    var tile = tileItems[address]
    if (!tile || !service.interactive) return
    tile.markClosing()
    service.closeWindow(address)
  }

  // ---- dragging windows ----------------------------------------------------------------

  property string dragAddress: ""
  property point dragPoint: Qt.point(0, 0)
  property point dragGrab: Qt.point(0.5, 0.5)
  property var dropTarget: null
  readonly property bool dragging: dragAddress !== ""
  // Windows shrink as they near the Spaces bar, like on macOS.
  readonly property real dragShrink: {
    var near = spacesBar.y + spacesBar.height + 170
    return 1 - 0.62 * smooth(0, 1, (near - dragPoint.y) / 170)
  }

  function beginDrag(address, point) {
    if (!mission || tileData[address] && tileData[address].minimized) return
    dragAddress = address
    dragPoint = point
    hoverAddress = ""
    selectedAddress = ""
  }

  function moveDrag(point) {
    dragPoint = point
    dropTarget = spacesBar.targetAt(point)
  }

  function endDrag(point) {
    var address = dragAddress
    var target = spacesBar.targetAt(point)
    var tile = tileItems[address]
    var info = tileData[address]
    var rect = spacesBar.rectFor(target)
    var moves = !!target && !(target.kind === "desktop" && target.id === monitor.activeWorkspace)
    // Start the flight from where the window was let go, before the drag
    // state (which positions it) is cleared.
    if (tile && moves && rect) tile.flyTo(rect, true)
    else if (tile && info) tile.flyTo(info.to, false)
    dragAddress = ""
    dropTarget = null
    if (!moves) return
    if (target.kind === "desktop") service.moveWindowToDesktop(address, target.id, screenName)
    else service.moveWindowToNewDesktop(address, screenName)
  }

  function cancelDrag() {
    var tile = tileItems[dragAddress]
    var info = tileData[dragAddress]
    if (tile && info) tile.flyTo(info.to, false)
    dragAddress = ""
    dropTarget = null
  }

  // ---- keyboard ---------------------------------------------------------------------------

  function step(direction) {
    var from = selectedAddress || hoverAddress
    if (!from || !placed[from]) {
      selectedAddress = tileIds.length ? tileIds[0] : ""
      return
    }
    var next = Layout.neighbor(placed, from, direction)
    if (next) selectedAddress = next
  }

  function cycle(forward) {
    if (tileIds.length === 0) return
    var ordered = tileIds.slice().sort(function(a, b) {
      var ra = placed[a], rb = placed[b]
      return Math.abs(ra.y - rb.y) > 20 ? ra.y - rb.y : ra.x - rb.x
    })
    var index = ordered.indexOf(selectedAddress || hoverAddress)
    index = index < 0 ? (forward ? 0 : ordered.length - 1) : (index + (forward ? 1 : -1) + ordered.length) % ordered.length
    selectedAddress = ordered[index]
  }

  // Keys come back here after a desktop's name has been edited.
  function focusKeys() { keys.forceActiveFocus() }

  function handleKey(event) {
    if (!service || !service.shown) return
    var key = event.key
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    event.accepted = true
    if (key === Qt.Key_Escape) service.close({})
    else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
      var target = selectedAddress || hoverAddress
      if (target) activate(target)
      else service.close({})
    } else if (ctrl && key === Qt.Key_W) {
      var closing = selectedAddress || hoverAddress
      if (closing) closeWindow(closing, "key")
    } else if (ctrl && key === Qt.Key_Left) service.stepDesktop(-1)
    else if (ctrl && key === Qt.Key_Right) service.stepDesktop(1)
    else if (key === Qt.Key_Left) step("left")
    else if (key === Qt.Key_Right) step("right")
    else if (key === Qt.Key_Up) step("up")
    else if (key === Qt.Key_Down) step("down")
    else if (key === Qt.Key_Tab) cycle(true)
    else if (key === Qt.Key_Backtab) cycle(false)
    else if (key >= Qt.Key_1 && key <= Qt.Key_9 && mission) {
      var desktop = desktopIds[key - Qt.Key_1]
      if (desktop !== undefined) service.close({ desktop: desktop })
    } else event.accepted = false
  }

  // ---- drawing ------------------------------------------------------------------------------

  Item {
    id: stage
    anchors.fill: parent
    // Nothing shows until the previews are ready; then it matches the screen.
    opacity: win.service && win.service.revealed ? (win.reduceMotion ? win.p : 1) : 0

    // The wallpaper, blurring and dimming as the stage opens.
    Item {
      id: backdrop
      anchors.fill: parent

      // Loaded the way Omarchy's own background loads the same file: off the
      // shell's main thread (so a slow or never-ending file can't stall the
      // shell) and from the shared image cache.
      Image {
        id: wallpaper
        anchors.fill: parent
        source: win.service ? win.service.wallpaperUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
      }

      MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: win.settings.background !== "dim" && opacity > 0.01
        opacity: win.smooth(0, 0.6, win.e)
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        saturation: 0.25
        autoPaddingEnabled: false
      }

      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: (win.settings.dim === undefined ? 25 : win.settings.dim) / 100 * win.e
      }
    }

    // The backdrop as one texture, for the Liquid Glass panes to refract.
    // Half resolution with mipmaps: the panes read it frosted anyway.
    ShaderEffectSource {
      id: glassBackdrop
      sourceItem: backdrop
      textureSize: Qt.size(Math.max(1, Math.round(win.width / 2)), Math.max(1, Math.round(win.height / 2)))
      live: true
      mipmap: true
      hideSource: false
      visible: false
    }

    // The screen as it was when the overlay appeared. The bar (and anything
    // else Hyprland reserves room for) slides away from it, and each window's
    // title bar and border ride along with the window and fade, so nothing
    // blinks out when the stage takes over the screen.
    ScreencopyView {
      id: screenGhost
      readonly property var reserved: win.monitor ? win.monitor.reserved : null
      readonly property bool wanted: !!reserved && (reserved.top + reserved.bottom + reserved.left + reserved.right) > 0
      readonly property real fade: win.smooth(0, 0.35, win.p)
      anchors.fill: parent
      // One frame per opening: set when the overlay appears, cleared when it goes.
      captureSource: win.showsHere ? win.modelData : null
      live: false
      visible: false
    }

    Repeater {
      model: screenGhost.wanted ? [
        { edge: "top", size: screenGhost.reserved.top },
        { edge: "bottom", size: screenGhost.reserved.bottom },
        { edge: "left", size: screenGhost.reserved.left },
        { edge: "right", size: screenGhost.reserved.right }
      ].filter(function(strip) { return strip.size > 0 }) : []

      delegate: Item {
        id: strip
        required property var modelData
        readonly property bool horizontal: modelData.edge === "top" || modelData.edge === "bottom"
        readonly property real slide: modelData.size * screenGhost.fade
        x: modelData.edge === "right" ? win.width - modelData.size + slide : modelData.edge === "left" ? -slide : 0
        y: modelData.edge === "bottom" ? win.height - modelData.size + slide : modelData.edge === "top" ? -slide : 0
        width: horizontal ? win.width : modelData.size
        height: horizontal ? modelData.size : win.height
        clip: true
        opacity: 1 - screenGhost.fade
        visible: opacity > 0.01 && screenGhost.hasContent

        ShaderEffectSource {
          sourceItem: screenGhost
          x: -(strip.modelData.edge === "right" ? win.width - strip.modelData.size : 0)
          y: -(strip.modelData.edge === "bottom" ? win.height - strip.modelData.size : 0)
          width: win.width
          height: win.height
          live: false
          hideSource: false
        }
      }
    }

    // Everything else layer-shell draws above the windows (a dock,
    // notifications): shown from the capture, fading out quickly as Mission
    // Control opens and back in as it closes. Drawn over the windows, as they
    // were on screen.
    Repeater {
      model: win.showsHere && win.monitor && win.service ? Model.surfaces(win.service.layers, win.monitor).filter(function(surface) {
        return surface.namespace !== "omarchy-bar"
      }) : []

      delegate: ShaderEffectSource {
        required property var modelData
        x: modelData.x
        y: modelData.y
        width: modelData.w
        height: modelData.h
        z: 1050
        sourceItem: screenGhost
        sourceRect: Qt.rect(modelData.x, modelData.y, modelData.w, modelData.h)
        live: false
        hideSource: false
        opacity: 1 - win.smooth(0, 0.22, win.p)
        visible: opacity > 0.01 && screenGhost.hasContent
      }
    }

    // Clicking the background goes back to the desktop.
    MouseArea {
      anchors.fill: parent
      enabled: !!win.service && win.service.interactive
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(event) {
        if (event.button === Qt.RightButton) {
          win.service.close({})
          win.service.openSettings("")
        } else {
          win.service.close({})
        }
      }
    }

    // App names under each group of windows ("Group windows by application").
    Repeater {
      model: win.grouped ? win.groups : []
      delegate: Row {
        required property var modelData
        spacing: 8
        x: modelData.x + (modelData.w - width) / 2
        y: modelData.y + modelData.h + 12
        opacity: win.smooth(0.6, 1, win.p)
        visible: opacity > 0.01

        IconImage {
          source: modelData.icon
          implicitSize: 30
          anchors.verticalCenter: parent.verticalCenter
          asynchronous: true
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.name
          textFormat: Text.PlainText
          color: "white"
          font.family: win.uiFont
          font.pixelSize: 14
          font.weight: Font.DemiBold
          style: Text.Raised
          styleColor: Qt.rgba(0, 0, 0, 0.35)
        }
      }
    }

    // App Exposé: the app's name and icon at the top, and a line above the
    // minimized windows.
    Row {
      visible: !!win.service && win.service.mode === "expose" && opacity > 0.01
      anchors.horizontalCenter: parent.horizontalCenter
      y: 30
      spacing: 10
      opacity: win.smooth(0.4, 1, win.p)
      readonly property var app: win.service && win.service.exposeClass ? win.service.appFor(win.service.exposeClass) : null

      IconImage {
        source: parent.app ? parent.app.icon : ""
        implicitSize: 36
        anchors.verticalCenter: parent.verticalCenter
        asynchronous: true
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: parent.app ? parent.app.name : ""
        textFormat: Text.PlainText
        color: "white"
        font.family: win.uiFont
        font.pixelSize: 20
        font.weight: Font.DemiBold
      }
    }

    Rectangle {
      visible: win.minimizedIds.length > 0 && !!win.service && win.service.mode === "expose"
      x: Math.round(win.width * 0.06)
      width: win.width - x * 2
      y: win.height - Math.round(win.height * 0.2) - 44
      height: 1
      color: Qt.rgba(1, 1, 1, 0.25)
      opacity: win.smooth(0.5, 1, win.p)
    }

    Repeater {
      model: ScriptModel { values: win.tileIds }
      delegate: WindowTile { overview: win }
    }

    // While a desktop is renamed, a click anywhere but its name keeps the
    // name and does nothing else. The Spaces bar is above this; its desktops
    // and "+" turn their clicks off meanwhile, so theirs land here too.
    MouseArea {
      anchors.fill: parent
      z: 1090
      enabled: spacesBar.renamingDesktop !== 0
      hoverEnabled: enabled
      acceptedButtons: Qt.AllButtons
      onPressed: spacesBar.commitRename()
    }

    SpacesBar {
      id: spacesBar
      overview: win
      visible: win.mission
      z: 1100
    }

    Item {
      id: keys
      focus: true
      Keys.onPressed: function(event) { win.handleKey(event) }
    }
  }
}
