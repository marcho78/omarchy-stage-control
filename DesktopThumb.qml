import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

// One desktop in the Spaces bar. Collapsed it is just its name; expanded it
// shows the desktop: the wallpaper with its windows where they are. Click to
// go there, hover for the delete button, drag it to reorder desktops, drop
// windows on it to move them there, and right-click it to rename it.
Item {
  id: thumb

  required property var modelData       // desktop (workspace) id
  property var strip: null

  readonly property var overview: strip ? strip.overview : null
  readonly property var service: strip ? strip.service : null
  readonly property var info: overview && overview.desktopData ? (overview.desktopData[modelData] || null) : null
  readonly property bool active: !!info && info.active
  readonly property real ex: strip ? strip.expand : 0
  readonly property bool hovered: hover.hovered
  readonly property bool dropTarget: !!overview && !!overview.dropTarget
    && overview.dropTarget.kind === "desktop" && overview.dropTarget.id === modelData
  readonly property bool reorderTarget: !!strip && strip.reorderTargetId === modelData && strip.draggingDesktop !== modelData
  readonly property bool beingDragged: !!strip && strip.draggingDesktop === modelData
  // The name you gave it, else a full-screen app's name, else Hyprland's.
  readonly property string customName: service && service.desktopNames ? (service.desktopNames[String(modelData)] || "") : ""
  readonly property string defaultLabel: !info ? "" : info.fullscreenClass
    ? (service ? service.appFor(info.fullscreenClass).name : info.fullscreenClass)
    : /^[0-9]+$/.test(info.name) ? "Desktop " + info.name : info.name
  readonly property string label: customName !== "" ? customName : defaultLabel

  readonly property bool renaming: !!strip && strip.renamingDesktop === modelData
  onRenamingChanged: {
    if (!renaming) return
    nameInput.text = label
    nameInput.selectAll()
    nameInput.forceActiveFocus()
  }

  // Keeping the default name (or clearing it) stores no name.
  function commitRename() {
    if (!renaming) return
    var text = nameInput.text.trim()
    strip.endRename(modelData, text === defaultLabel ? "" : text)
  }

  readonly property real pillWidth: (renaming ? Math.max(64, nameInput.implicitWidth + 4) : labelText.implicitWidth) + 26
  width: Math.round(pillWidth + (Math.max(strip ? strip.thumbW : 0, pillWidth) - pillWidth) * ex)
  height: strip ? strip.thumbH + 10 + strip.labelH : 0

  // Where the thumbnail is, in the overview's coordinates (for drops).
  function pictureRect() {
    var point = picture.mapToItem(overview.stage, 0, 0)
    return { x: point.x, y: point.y, w: picture.width * picture.scale, h: picture.height * picture.scale }
  }

  // While another desktop is dragged over this one, make room for it.
  transform: Translate {
    x: thumb.beingDragged ? thumb.strip.desktopDragOffset : 0
  }
  z: beingDragged ? 10 : 0

  Item {
    id: picture
    anchors.horizontalCenter: parent.horizontalCenter
    width: strip ? strip.thumbW : 0
    height: strip ? strip.thumbH : 0
    opacity: thumb.ex
    visible: opacity > 0.01
    scale: (0.72 + 0.28 * thumb.ex) * (thumb.dropTarget || thumb.reorderTarget ? 1.06 : thumb.hovered && !thumb.beingDragged ? 1.03 : 1)
    transformOrigin: Item.Top
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    RectangularShadow {
      anchors.fill: parent
      radius: 9
      offset: Qt.vector2d(0, 5)
      blur: 16
      spread: -2
      color: Qt.rgba(0, 0, 0, 0.45)
    }

    ClippingRectangle {
      id: screenPicture
      anchors.fill: parent
      radius: 9
      color: Qt.rgba(0.1, 0.1, 0.12, 1)

      Image {
        anchors.fill: parent
        source: thumb.service ? thumb.service.wallpaperUrl : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.round(thumb.strip ? thumb.strip.thumbW * 2 : 0)
        asynchronous: true
        cache: true
        smooth: true
      }

      // The desktop's windows, where they are on the display.
      Repeater {
        model: ScriptModel { values: thumb.info && thumb.ex > 0.01 ? thumb.info.windows : [] }
        delegate: Item {
          id: mini
          required property var modelData
          readonly property var win: thumb.overview ? thumb.overview.windowFor(modelData) : null
          readonly property var mon: thumb.overview ? thumb.overview.monitor : null
          readonly property real s: mon ? picture.width / Math.max(1, mon.w) : 0
          readonly property var handle: {
            Hyprland.toplevels.values
            return thumb.service ? thumb.service.toplevelFor(modelData) : null
          }
          visible: !!win && !!mon
          x: win && mon ? (win.x - mon.x) * s : 0
          y: win && mon ? (win.y - mon.y) * s : 0
          width: win ? Math.max(2, win.w * s) : 0
          height: win ? Math.max(2, win.h * s) : 0
          z: win ? (win.floating ? 200 : 0) + (100 - Math.min(99, win.focus)) : 0

          Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: 2
            color: Qt.rgba(0, 0, 0, 0.25)
          }
          ScreencopyView {
            anchors.fill: parent
            captureSource: thumb.overview && thumb.overview.showsHere && mini.handle ? mini.handle.wayland : null
            // The desktop on screen is live; the others hold the frame they had.
            live: thumb.active
          }
        }
      }
    }

    // Frame: bright for the desktop on screen, the highlight color for drops.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -3
      radius: 12
      color: "transparent"
      border.width: thumb.dropTarget || thumb.reorderTarget ? 3 : thumb.active ? 2.5 : 1
      border.color: thumb.dropTarget || thumb.reorderTarget || thumb.active ? (thumb.overview ? thumb.overview.highlight : "#0a84ff")
        : Qt.rgba(1, 1, 1, thumb.hovered ? 0.45 : 0.16)
      Behavior on border.color { ColorAnimation { duration: 140 } }
    }

    // Delete, top-left, like macOS. The last desktop can't be removed.
    Glass {
      id: removeButton
      readonly property bool wanted: thumb.hovered && thumb.ex > 0.9 && !!thumb.strip && thumb.strip.count > 1
        && !thumb.overview.dragging && thumb.strip.draggingDesktop === 0 && thumb.strip.renamingDesktop === 0
      x: -9
      y: -9
      width: 22
      height: 22
      radius: 11
      style: "solid"
      selected: removeMouse.containsMouse
      selectedColor: "#ff5f57"
      selectedStrength: 0.95
      opacity: wanted ? 1 : 0
      visible: opacity > 0.01
      scale: wanted ? 1 : 0.6
      Behavior on opacity { NumberAnimation { duration: 140 } }
      Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
      z: 5

      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        text: "×"
        textFormat: Text.PlainText
        color: removeMouse.containsMouse ? Qt.rgba(0.36, 0.04, 0.02, 1) : "white"
        font.pixelSize: 16
        font.weight: Font.DemiBold
        font.family: thumb.overview ? thumb.overview.uiFont : ""
      }
      MouseArea {
        id: removeMouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        enabled: removeButton.wanted
        cursorShape: Qt.PointingHandCursor
        onClicked: thumb.service.removeDesktop(thumb.overview.screenName, thumb.modelData)
      }
    }
  }

  // Name: a glass pill under the thumbnail (or on its own when collapsed).
  Glass {
    id: pill
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round((thumb.strip ? thumb.strip.thumbH + 10 : 0) * thumb.ex)
    width: thumb.pillWidth
    height: thumb.strip ? thumb.strip.labelH : 24
    radius: height / 2
    style: thumb.overview ? thumb.overview.glassStyle : "liquid"
    backdrop: thumb.overview ? thumb.overview.glassBackdrop : null
    backdropSpace: thumb.overview ? thumb.overview.stage : null
    shadow: thumb.ex < 0.5
    hovered: thumb.hovered && !thumb.active
    selected: thumb.active
    selectedColor: thumb.overview ? thumb.overview.highlight : "#0a84ff"
    selectedStrength: 0.26
    outlineColor: thumb.overview ? thumb.overview.highlight : "#0a84ff"
    outlineWidth: thumb.active || thumb.renaming ? 1.5 : 0

    Text {
      id: labelText
      anchors.centerIn: parent
      visible: !thumb.renaming
      text: thumb.label
      textFormat: Text.PlainText
      color: Qt.rgba(1, 1, 1, thumb.active ? 1 : 0.78)
      font.family: thumb.overview ? thumb.overview.uiFont : ""
      font.pixelSize: 12
      font.weight: thumb.active ? Font.DemiBold : Font.Medium
    }

    // The name, editable, while renaming. Enter keeps it, Esc cancels; the
    // keys stop here, so the stage's own (Esc closes it) never see them.
    TextInput {
      id: nameInput
      anchors.centerIn: parent
      width: thumb.pillWidth - 26
      visible: thumb.renaming
      enabled: thumb.renaming
      horizontalAlignment: TextInput.AlignHCenter
      clip: true
      maximumLength: 32
      selectByMouse: true
      color: "white"
      selectionColor: thumb.overview ? thumb.overview.highlight : "#0a84ff"
      selectedTextColor: "white"
      font.family: thumb.overview ? thumb.overview.uiFont : ""
      font.pixelSize: 12
      font.weight: Font.DemiBold
      onActiveFocusChanged: if (!activeFocus && thumb.renaming) thumb.commitRename()
      Keys.onReturnPressed: function(event) { event.accepted = true; thumb.commitRename() }
      Keys.onEnterPressed: function(event) { event.accepted = true; thumb.commitRename() }
      Keys.onEscapePressed: function(event) { event.accepted = true; thumb.strip.endRename(thumb.modelData, null) }
      Keys.onTabPressed: function(event) { event.accepted = true }
      Keys.onBacktabPressed: function(event) { event.accepted = true }
    }
  }

  HoverHandler {
    id: hover
    enabled: !!thumb.service && thumb.service.interactive
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    // Off while any desktop is renamed: a click then only keeps the name.
    enabled: !!thumb.service && thumb.service.interactive && !!thumb.strip && thumb.strip.renamingDesktop === 0
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: thumb.beingDragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    // Under the delete button.
    z: -1
    property real pressedX: 0

    onPressed: function(event) {
      if (event.button === Qt.RightButton) {
        thumb.strip.beginRename(thumb.modelData)
        return
      }
      pressedX = mapToItem(thumb.strip, event.x, event.y).x
    }
    onPositionChanged: function(event) {
      if (!(pressedButtons & Qt.LeftButton) || thumb.ex < 0.9) return
      var x = mapToItem(thumb.strip, event.x, event.y).x
      if (thumb.strip.draggingDesktop === 0 && Math.abs(x - pressedX) > 12) thumb.strip.beginDesktopDrag(thumb.modelData, pressedX)
      if (thumb.strip.draggingDesktop === thumb.modelData) thumb.strip.moveDesktopDrag(x)
    }
    onReleased: function(event) {
      if (event.button !== Qt.LeftButton) return
      if (thumb.strip.draggingDesktop === thumb.modelData) {
        thumb.strip.endDesktopDrag()
        return
      }
      if (thumb.info && thumb.info.active) thumb.service.close({})
      else thumb.service.close({ desktop: thumb.modelData })
    }
    onCanceled: if (thumb.strip.draggingDesktop === thumb.modelData) thumb.strip.cancelDesktopDrag()
  }

  Component.onCompleted: if (strip) strip.registerThumb(modelData, thumb)
  Component.onDestruction: {
    if (!strip) return
    strip.unregisterThumb(modelData, thumb)
    if (renaming) strip.endRename(modelData, null)
  }
}
