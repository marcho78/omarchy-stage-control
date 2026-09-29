import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "stage" as Stage

// Runs Stage Control outside the Omarchy shell (see dev/run). Hyprland registration is
// off, and the overlays sit on the background layer, under your windows, and
// never take the keyboard, so you can keep working while scripts drive it:
//
//   qs ipc -p <dir> call stage-control-dev open mission
//   qs ipc -p <dir> call stage-control-dev progress 0.5
//   qs ipc -p <dir> call stage-control-dev grab eDP-1 /tmp/stage-control.png
ShellRoot {
  id: root

  Stage.Service {
    id: service
    hyprIntegration: false
    testMode: true
    shell: QtObject {
      function summon(id, payload) { console.log("harness: summon", id, payload); return true }
      function updateEntryInline(id, settings) { console.log("harness: settings", JSON.stringify(settings)); return true }
    }
  }

  // The settings window's content, under your windows, for screenshots.
  PanelWindow {
    id: settingsWindow
    visible: false
    anchors { bottom: true; right: true }
    implicitWidth: 860
    implicitHeight: 680
    color: Color.background
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "marcho78-stage-control-dev"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      id: settingsFrame
      anchors.fill: parent
      color: Color.background

      Stage.SettingsView {
        id: settingsView
        anchors.fill: parent
        service: service
      }
    }
  }

  IpcHandler {
    target: "stage-control-dev"

    function settingsPage(page: string, path: string): void {
      settingsWindow.visible = true
      settingsView.page = page
      grabTimer.path = path
      grabTimer.restart()
    }

    function open(mode: string): void { service.open(mode || "mission") }
    function close(): void { service.close({}) }
    function exposeApp(appClass: string): void { service.exposeApp(appClass) }
    function finish(): void { service.finishClose() }

    // Freeze the animation at a point, 0..1.
    function progress(value: string): void {
      service.revealed = true
      service.tracking = true
      service.progress = Number(value)
    }

    function set(key: string, value: string): void {
      var next = JSON.parse(JSON.stringify(service.user))
      try { next[key] = JSON.parse(value) } catch (e) { next[key] = value }
      service.user = next
    }

    function hover(screen: string, address: string): void {
      var overview = service.overviews[screen]
      if (overview) overview.hoverAddress = address
    }

    function closeWindow(screen: string, address: string): void {
      var overview = service.overviews[screen]
      if (overview) overview.closeWindow(address, "button")
    }

    function expand(screen: string, on: string): void {
      var overview = service.overviews[screen]
      if (overview) overview.forceExpanded = on === "true"
    }

    function drag(screen: string, address: string, x: string, y: string): void {
      var overview = service.overviews[screen]
      if (!overview) return
      if (address === "") {
        overview.cancelDrag()
        return
      }
      if (overview.dragAddress !== address) overview.beginDrag(address, Qt.point(Number(x), Number(y)))
      overview.moveDrag(Qt.point(Number(x), Number(y)))
    }

    // Feed a gesture step as if it came from hypr/stage.lua.
    function gesture(phase: string, dy: string, time: string): void {
      service.handleEvent({ type: "gesture", phase: phase, dx: 0, dy: Number(dy), time: Number(time), fingers: 5, cancelled: false })
    }

    function state(): string {
      return JSON.stringify({
        mode: service.mode, progress: service.progress, revealed: service.revealed,
        tracking: service.tracking, closing: service.closing, snap: !!service.snap,
        screens: Object.keys(service.overviews), font: service.uiFont, wallpaper: service.wallpaper
      })
    }

    function tiles(screen: string): string {
      var overview = service.overviews[screen]
      return overview ? JSON.stringify({ ids: overview.tileIds, data: overview.tileData, desktops: overview.desktopIds }) : "{}"
    }

    function bar(screen: string): string {
      var overview = service.overviews[screen]
      if (!overview) return "no overview"
      var bar = overview.spacesBar
      var out = { bar: { x: bar.x, y: bar.y, w: bar.width, h: bar.height, visible: bar.visible, opacity: bar.opacity, expand: bar.expand, count: bar.count, thumbW: bar.thumbW, thumbH: bar.thumbH }, thumbs: {} }
      for (var id in bar.thumbs) {
        var t = bar.thumbs[id]
        var at = t.mapToItem(overview.stage, 0, 0)
        out.thumbs[id] = { x: at.x, y: at.y, w: t.width, h: t.height, visible: t.visible, opacity: t.opacity, label: t.label, info: t.info }
      }
      return JSON.stringify(out)
    }

    function settingsHide(): void { settingsWindow.visible = false }

    function grab(screen: string, path: string): void {
      var overview = service.overviews[screen]
      if (!overview) {
        console.log("harness: no overview for", screen)
        return
      }
      overview.stage.grabToImage(function(result) {
        console.log("harness: grabbed", path, result.saveToFile(path))
      })
    }
  }

  Timer {
    id: grabTimer
    property string path: ""
    interval: 700
    onTriggered: settingsFrame.grabToImage(function(result) { console.log("harness: grabbed", path, result.saveToFile(path)) })
  }
}
