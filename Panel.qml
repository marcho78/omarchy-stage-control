import QtQuick
import Quickshell
import qs.Commons

// The Stage Control settings window. Open it with
// `omarchy-shell stage-control settings`, a right-click in Mission Control, or
//   omarchy-shell shell summon marcho78.stage-control '{}'
//
// Settings live on Stage Control's entry in ~/.config/omarchy/shell.json (only
// what differs from Defaults.js) and apply as you change them.
Item {
  id: root

  property var shell: null
  property var service: null
  property bool closingFromHost: false

  readonly property string pluginId: "marcho78.stage-control"

  // Payload may name a page: { "page": "corners" }.
  function open(payloadJson) {
    closingFromHost = false
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload && view.pages.some(function(p) { return p.id === payload.page })) view.page = payload.page
    } catch (e) { /* ignore a bad payload */ }
    var alreadyOpen = window.visible
    window.visible = true
    // Opening it again brings the window back, even from another workspace.
    if (alreadyOpen) Quickshell.execDetached(["/usr/bin/hyprctl", "dispatch", 'hl.dsp.focus({ window = "title:^Stage Control$" })'])
  }

  // Host-initiated close (`shell hide`).
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  // User-initiated close (Esc, the window's close button): tell the shell so
  // its open-panel state stays in sync.
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else window.visible = false
  }

  FloatingWindow {
    id: window
    title: "Stage Control"
    color: Color.background
    implicitWidth: 860
    implicitHeight: 680
    minimumSize: Qt.size(760, 580)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide(root.pluginId)
    }

    FocusScope {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.requestClose()

      SettingsView {
        id: view
        anchors.fill: parent
        service: root.service
      }
    }
  }
}
