import QtQuick
import qs.Ui

// Stage Control's icon in the Omarchy bar. Click for its settings, right-click
// to open the stage, middle-click for App Exposé.
//
// For Omarchy this icon is also Stage Control's on switch: a third-party plugin
// is on while its entry is in the bar. To keep Stage Control but lose the icon,
// turn off "Show Stage Control in the top bar" in its settings; the icon then
// takes no space.
BarWidget {
  id: root
  moduleName: "marcho78.stage-control"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("marcho78.stage-control") : null
  readonly property bool wanted: !service || !service.settings || service.settings.barIcon !== false

  visible: wanted
  implicitWidth: wanted ? button.implicitWidth : 0
  implicitHeight: wanted ? button.implicitHeight : 0

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Material Design "view dashboard": windows of different sizes, spread out.
    text: String.fromCodePoint(0xf056e)
    tooltipText: "Stage Control · click for settings, right-click to open the stage"
    onPressed: function(button) {
      if (!root.service) return
      if (button === Qt.RightButton) root.service.open("mission")
      else if (button === Qt.MiddleButton) root.service.open("expose")
      else root.service.openSettings("")
    }
  }
}
