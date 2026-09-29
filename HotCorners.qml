import QtQuick
import Quickshell
import Quickshell.Wayland

// macOS hot corners for one display: push the pointer into a corner to run
// the action picked for it in settings. Only corners with an action get a
// surface, two pixels square, on top of everything; it takes the clicks on
// those pixels, so leave a corner empty if you click things there.
Scope {
  id: corners

  required property var modelData       // the ShellScreen
  property var service: null

  readonly property var settings: service && service.settings ? service.settings : ({})

  component Corner: PanelWindow {
    id: corner

    property string action: "none"
    property bool atTop: true
    property bool atLeft: true
    // After firing, wait for the pointer to leave before firing again.
    property bool armed: true

    screen: corners.modelData
    visible: action !== "none" && !!corners.service && !corners.service.shown
    anchors {
      top: corner.atTop
      bottom: !corner.atTop
      left: corner.atLeft
      right: !corner.atLeft
    }
    implicitWidth: 2
    implicitHeight: 2
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "marcho78-stage-control-corner"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onEntered: if (corner.armed) dwell.restart()
      onExited: {
        dwell.stop()
        corner.armed = true
      }
    }

    Timer {
      id: dwell
      // Brushing past a corner shouldn't count.
      interval: 90
      onTriggered: {
        corner.armed = false
        corners.service.runCornerAction(corner.action)
      }
    }
  }

  Corner { action: corners.settings.cornerTopLeft || "none"; atTop: true; atLeft: true }
  Corner { action: corners.settings.cornerTopRight || "none"; atTop: true; atLeft: false }
  Corner { action: corners.settings.cornerBottomLeft || "none"; atTop: false; atLeft: true }
  Corner { action: corners.settings.cornerBottomRight || "none"; atTop: false; atLeft: false }
}
