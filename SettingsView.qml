import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "Settings.js" as Settings

// What the Stage Control settings window shows: a live preview of the stage in
// the current settings, a page list, and the pages. Panel.qml puts it in a
// window.
Item {
  id: root

  property var service: null
  property string page: "mission"

  // ---- settings ----------------------------------------------------------------

  readonly property bool ready: !!service && !!service.settings
  readonly property var settings: ready ? service.settings : ({})
  readonly property bool customized: ready && Object.keys(service.user || {}).length > 0

  function set(key, value) {
    if (ready) service.setSetting(key, value)
  }

  property bool resetConfirmOpen: false

  readonly property var pages: [
    { id: "mission", label: "Stage", glyph: "󰕰" },
    { id: "gestures", label: "Trackpad", glyph: "󰟸" },
    { id: "keys", label: "Shortcuts", glyph: "󰌌" },
    { id: "corners", label: "Hot Corners", glyph: "󱂬" },
    { id: "look", label: "Appearance", glyph: "󰏘" }
  ]

  readonly property var cornerActions: [
    { value: "none", label: "—" },
    { value: "stage", label: "Open the stage" },
    { value: "appWindows", label: "Application Windows" },
    { value: "launchpad", label: "Apps (Launchpad)" },
    { value: "menu", label: "Omarchy Menu" },
    { value: "lock", label: "Lock Screen" },
    { value: "screensaver", label: "Start Screen Saver" }
  ]

  readonly property var highlightChoices: [
    { value: "accent", label: "Theme", color: Color.accent },
    { value: "blue", label: "Blue", color: "#0a84ff" },
    { value: "purple", label: "Purple", color: "#bf5af2" },
    { value: "pink", label: "Pink", color: "#ff375f" },
    { value: "red", label: "Red", color: "#ff453a" },
    { value: "orange", label: "Orange", color: "#ff9f0a" },
    { value: "yellow", label: "Yellow", color: "#ffd60a" },
    { value: "green", label: "Green", color: "#32d74b" },
    { value: "graphite", label: "Graphite", color: "#98989d" }
  ]

  // Shortcut text fields: what was typed, checked like the service checks it.
  function shortcutProblem(text) {
    if (String(text).trim() === "") return ""
    return Settings.parseShortcut(String(text)) ? "" : "Use modifiers and a key, like SUPER + A or CTRL + UP."
  }

  // PanelSlider takes its colors from a bar object.
  readonly property QtObject sliderBar: QtObject {
    readonly property color foreground: Color.foreground
    readonly property color background: Color.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: Style.font.family
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }

  component SectionLabel: PanelSectionHeader {
    width: parent ? parent.width : 0
    topPadding: 10
    foreground: Color.foreground
    fontFamily: Style.font.family
  }

  component Caption: Text {
    width: parent ? parent.width : 0
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    color: Color.foreground
    opacity: 0.55
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  component SliderRow: Column {
    id: sliderRow
    property string key: ""
    property string label: ""
    property string unit: "%"
    property var bounds: [0, 100]
    width: parent ? parent.width : 0
    spacing: 6

    Item {
      width: parent.width
      height: rowLabel.implicitHeight
      Text {
        id: rowLabel
        textFormat: Text.PlainText
        text: sliderRow.label
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: Math.round(slider.dragging ? slider.liveValue : (root.settings[sliderRow.key] || 0)) + sliderRow.unit
        color: Color.foreground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.sliderBar
      minimum: sliderRow.bounds[0]
      maximum: sliderRow.bounds[1]
      step: 1
      integer: true
      value: root.settings[sliderRow.key] || 0
      onMoved: function(v) { root.set(sliderRow.key, Math.round(v)) }
      onReleased: function(v) { root.set(sliderRow.key, Math.round(v)) }
    }
  }

  component ShortcutField: Column {
    id: shortcutField
    property string key: ""
    property string label: ""
    width: parent ? parent.width : 0
    spacing: 6

    Text {
      textFormat: Text.PlainText
      text: shortcutField.label
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Row {
      spacing: 8
      TextField {
        id: keysField
        width: Math.min(280, shortcutField.width - 110)
        placeholderText: "None"
        text: root.settings[shortcutField.key] || ""
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        onEditingFinished: {
          if (root.shortcutProblem(text) === "") root.set(shortcutField.key, text.trim())
        }
      }
      Button {
        anchors.verticalCenter: parent.verticalCenter
        bordered: true
        text: "Default"
        enabled: root.ready && root.settings[shortcutField.key] !== root.service.defaults[shortcutField.key]
        opacity: enabled ? 1 : 0.4
        onClicked: root.set(shortcutField.key, root.service.defaults[shortcutField.key])
      }
    }
    Caption {
      visible: text !== ""
      text: root.shortcutProblem(keysField.text)
      color: Color.urgent
      opacity: 1
    }
  }


  // ---- live preview: a small stage in the current settings.
  Item {
    id: hero
    width: parent.width
    height: 210
    clip: true

    readonly property color highlight: root.ready ? root.service.highlight : Color.accent
    readonly property string glassStyle: root.settings.glass || "liquid"

    Item {
      id: heroBackdrop
      anchors.fill: parent

      Image {
        id: heroWallpaper
        anchors.fill: parent
        source: root.ready ? root.service.wallpaperUrl : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1200
        asynchronous: true
      }
      MultiEffect {
        anchors.fill: parent
        source: heroWallpaper
        visible: root.settings.background !== "dim"
        blurEnabled: true
        blurMax: 48
        blur: 1
        saturation: 0.25
        autoPaddingEnabled: false
      }
      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: (root.settings.dim === undefined ? 25 : root.settings.dim) / 100
      }
    }

    ShaderEffectSource {
      id: heroGlass
      sourceItem: heroBackdrop
      live: true
      mipmap: true
      hideSource: false
      visible: false
    }

    // Desktops.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 14
      spacing: 10
      Repeater {
        model: ["Desktop 1", "Desktop 2", "Desktop 3"]
        Glass {
          id: deskPill
          required property string modelData
          required property int index
          width: deskLabel.implicitWidth + 22
          height: 20
          style: hero.glassStyle
          backdrop: heroGlass
          backdropSpace: hero
          selected: index === 0
          selectedColor: hero.highlight
          selectedStrength: 0.26
          outlineColor: hero.highlight
          outlineWidth: index === 0 ? 1.5 : 0
          Text {
            id: deskLabel
            anchors.centerIn: parent
            text: deskPill.modelData
            textFormat: Text.PlainText
            color: "white"
            font.family: root.ready ? root.service.uiFont : Style.font.family
            font.pixelSize: 10
            font.weight: deskPill.index === 0 ? Font.DemiBold : Font.Medium
          }
        }
      }
    }

    Glass {
      x: parent.width - width - 16
      y: 10
      width: 28
      height: 28
      radius: 8
      style: hero.glassStyle
      backdrop: heroGlass
      backdropSpace: hero
      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -1
        text: "+"
        textFormat: Text.PlainText
        color: "white"
        font.pixelSize: 18
        font.weight: Font.Light
      }
    }

    // Windows.
    Repeater {
      model: [
        { x: 0.08, y: 0.30, w: 0.26, h: 0.50, title: "Files — Documents", lit: false },
        { x: 0.37, y: 0.26, w: 0.30, h: 0.56, title: "Terminal — ~/projects", lit: true },
        { x: 0.70, y: 0.26, w: 0.22, h: 0.44, title: "Browser — omarchy.org", lit: false }
      ]
      Item {
        id: fake
        required property var modelData
        // A window above the Try button stops short, so its title (8px down,
        // 18px tall) stays clear of the button.
        readonly property bool overButton: x + width > tryButton.x
        x: modelData.x * hero.width
        y: modelData.y * hero.height
        width: modelData.w * hero.width
        height: overButton ? Math.max(0, Math.min(modelData.h * hero.height, tryButton.y - 6 - 26 - y))
          : modelData.h * hero.height

        RectangularShadow {
          anchors.fill: parent
          radius: 8
          blur: 16
          offset: Qt.vector2d(0, 5)
          color: Qt.rgba(0, 0, 0, 0.45)
        }
        Rectangle {
          anchors.fill: parent
          radius: 8
          color: Qt.lighter(Color.background, 1.15)
          Column {
            x: 10
            y: 10
            spacing: 6
            Repeater {
              model: 4
              Rectangle {
                required property int index
                width: fake.width * (0.7 - index * 0.12)
                height: 4
                radius: 2
                color: index === 0 ? Color.accent : Color.foreground
                opacity: index === 0 ? 0.8 : 0.25
              }
            }
          }
        }
        Rectangle {
          anchors.fill: parent
          anchors.margins: -4
          radius: 11
          color: "transparent"
          border.width: 2
          border.color: hero.highlight
          visible: fake.modelData.lit
        }
        Glass {
          visible: fake.modelData.lit && root.settings.windowTitles !== "never" || root.settings.windowTitles === "always"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.bottom
          anchors.topMargin: 8
          width: fakeTitle.implicitWidth + 18
          height: 18
          style: hero.glassStyle
          backdrop: heroGlass
          backdropSpace: hero
          Text {
            id: fakeTitle
            anchors.centerIn: parent
            text: fake.modelData.title
            textFormat: Text.PlainText
            color: "white"
            font.family: root.ready ? root.service.uiFont : Style.font.family
            font.pixelSize: 9
          }
        }
      }
    }

    Button {
      id: tryButton
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 10
      bordered: true
      background: Qt.rgba(0, 0, 0, 0.45)
      foreground: "white"
      iconText: "󰕰"
      text: "Try the stage"
      enabled: root.ready
      onClicked: root.service.open("mission")
    }
  }

  // ---- navigation, and reset.
  Column {
    id: nav
    anchors.top: hero.bottom
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.margins: 14
    width: 180
    spacing: 4

    Repeater {
      model: root.pages
      Button {
        required property var modelData
        width: nav.width
        leftAlign: true
        iconText: modelData.glyph
        text: modelData.label
        selected: root.page === modelData.id
        onClicked: root.page = modelData.id
      }
    }
  }

  Button {
    anchors.left: nav.left
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 14
    width: nav.width
    bordered: true
    iconText: "󰑓"
    text: "Reset to default"
    enabled: root.customized
    opacity: enabled ? 1 : 0.4
    onClicked: root.resetConfirmOpen = true
  }

  Rectangle {
    anchors.top: hero.bottom
    anchors.bottom: parent.bottom
    anchors.left: nav.right
    anchors.leftMargin: 14
    width: 1
    color: Color.foreground
    opacity: 0.1
  }

  Flickable {
    id: content
    anchors.top: hero.bottom
    anchors.bottom: parent.bottom
    anchors.left: nav.right
    anchors.right: parent.right
    anchors.leftMargin: 29
    anchors.rightMargin: 22
    anchors.topMargin: 12
    anchors.bottomMargin: 12
    contentHeight: pageColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: pageColumn
      width: content.width - 12
      spacing: 10

      // Problems registering with Hyprland.
      Rectangle {
        readonly property string problem: root.ready && root.service.hyprStatus !== "" && root.service.hyprStatus !== "ok" ? root.service.hyprStatus : ""
        visible: problem !== ""
        width: parent.width
        height: problemText.implicitHeight + 20
        color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.1)
        border.width: 1
        border.color: Color.urgent
        Text {
          id: problemText
          x: 10
          y: 10
          width: parent.width - 20
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: parent.problem.indexOf("overshadowed") >= 0
            ? "Your Hyprland config already has a gesture with this many fingers in this direction, so Stage Control's didn't register. Pick another finger count, or remove the other gesture."
            : "Hyprland didn't take Stage Control's gestures and shortcuts: " + parent.problem.slice(0, 400)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      // ---- the stage
      Column {
        visible: root.page === "mission"
        width: parent.width
        spacing: 10

        Toggle {
          width: parent.width
          label: "Show Stage Control in the top bar"
          description: "Click the icon for these settings, right-click to open the stage. Turned off, the icon takes no space; Stage Control keeps running."
          checked: root.settings.barIcon !== false
          onClicked: root.set("barIcon", root.settings.barIcon === false)
        }

        Toggle {
          width: parent.width
          label: "Group windows by application"
          description: "Windows from the same app sit together, under the app's icon and name."
          checked: root.settings.groupByApp === true
          onClicked: root.set("groupByApp", root.settings.groupByApp !== true)
        }

        SectionLabel { text: "Window titles" }
        ButtonGroup {
          options: [{ value: "hover", label: "On hover" }, { value: "always", label: "Always" }, { value: "never", label: "Never" }]
          value: root.settings.windowTitles || "hover"
          onChanged: function(v) { root.set("windowTitles", v) }
        }

        Toggle {
          width: parent.width
          label: "Show app icons"
          description: "Each window wears its app's icon on its bottom edge."
          checked: root.settings.appIcons !== false
          onClicked: root.set("appIcons", root.settings.appIcons === false)
        }

        SectionLabel { text: "Spaces bar" }
        ButtonGroup {
          options: [{ value: "auto", label: "Names, thumbnails on hover" }, { value: "expanded", label: "Always show thumbnails" }]
          value: root.settings.spacesBar || "auto"
          onChanged: function(v) { root.set("spacesBar", v) }
        }
        Caption { text: "Right-click a desktop in the Spaces bar to rename it." }

        Toggle {
          width: parent.width
          label: "Keep desktops numbered in order"
          description: "Removing a desktop moves the ones after it down, so Desktop 3 is always Super+3."
          checked: root.settings.renumberDesktops !== false
          onClicked: root.set("renumberDesktops", root.settings.renumberDesktops === false)
        }

        Toggle {
          width: parent.width
          label: "Close buttons on windows"
          description: "Hover a window for a × in its corner that closes it."
          checked: root.settings.closeButtons !== false
          onClicked: root.set("closeButtons", root.settings.closeButtons === false)
        }

        Toggle {
          width: parent.width
          label: "Middle-click closes windows"
          checked: root.settings.middleClickClose !== false
          onClicked: root.set("middleClickClose", root.settings.middleClickClose === false)
        }

        Toggle {
          width: parent.width
          label: "Minimized windows in App Exposé"
          description: "Windows minimized with Title Bars appear in a row at the bottom; click one to bring it back."
          checked: root.settings.showMinimized !== false
          onClicked: root.set("showMinimized", root.settings.showMinimized === false)
        }

        Caption {
          topPadding: 6
          text: "On the stage: click a window to go to it, drag it onto a desktop to move it there (or onto + for a new desktop), "
            + "drag desktops to reorder them, hover a desktop to remove it, hover a window and click × to close it. "
            + "Arrow keys pick a window, Return goes to it, Ctrl+W closes it, 1–9 jump to a desktop, "
            + "Ctrl+←/→ switch desktops, Esc leaves. Right-click the background for these settings."
        }
      }

      // ---- Trackpad
      Column {
        visible: root.page === "gestures"
        width: parent.width
        spacing: 10

        SectionLabel { text: "The stage"; topPadding: 0 }
        Caption { text: "Swipe up to open it, following your fingers, and down to close it." }
        ButtonGroup {
          options: [{ value: "0", label: "Off" }, { value: "3", label: "3 fingers" }, { value: "4", label: "4 fingers" }, { value: "5", label: "5 fingers" }]
          value: String(root.settings.gestureFingers === undefined ? 4 : root.settings.gestureFingers)
          onChanged: function(v) { root.set("gestureFingers", Number(v)) }
        }

        Toggle {
          width: parent.width
          label: "App Exposé"
          description: "Swipe down with the same fingers to see all windows of the app you're using."
          checked: root.settings.appExposeGesture !== false
          enabled: root.settings.gestureFingers !== 0
          opacity: enabled ? 1 : 0.5
          onClicked: root.set("appExposeGesture", root.settings.appExposeGesture === false)
        }

        SectionLabel { text: "Swipe between desktops" }
        Caption { text: "Swipe left or right to move between desktops. Leave this off if your Hyprland config already has a workspace swipe." }
        ButtonGroup {
          options: [{ value: "0", label: "Off" }, { value: "3", label: "3 fingers" }, { value: "4", label: "4 fingers" }, { value: "5", label: "5 fingers" }]
          value: String(root.settings.desktopSwipeFingers || 0)
          onChanged: function(v) { root.set("desktopSwipeFingers", Number(v)) }
        }
        Caption {
          visible: root.settings.desktopSwipeFingers !== 0 && root.settings.desktopSwipeFingers === root.settings.gestureFingers
          text: "The stage opens and closes with an up or down swipe and desktops swipe sideways, so the same fingers can do both."
        }
      }

      // ---- Shortcuts
      Column {
        visible: root.page === "keys"
        width: parent.width
        spacing: 10

        Toggle {
          width: parent.width
          label: "Keyboard shortcuts"
          description: "Stage Control adds these while it runs; your Hyprland config is never edited."
          checked: root.settings.shortcuts !== false
          onClicked: root.set("shortcuts", root.settings.shortcuts === false)
        }

        ShortcutField { key: "stageKey"; label: "Open the stage"; enabled: root.settings.shortcuts !== false; opacity: enabled ? 1 : 0.5 }
        ShortcutField { key: "appWindowsKey"; label: "Application windows"; enabled: root.settings.shortcuts !== false; opacity: enabled ? 1 : 0.5 }

        Toggle {
          width: parent.width
          label: "Mac keyboard shortcuts"
          description: "Ctrl+↑ opens the stage, Ctrl+↓ application windows, Ctrl+← and Ctrl+→ move between desktops, and F3 on Mac keyboards opens the stage too. Ctrl+arrows jump by word in most Linux text fields, so this is off by default."
          checked: root.settings.macShortcuts === true
          enabled: root.settings.shortcuts !== false
          opacity: enabled ? 1 : 0.5
          onClicked: root.set("macShortcuts", root.settings.macShortcuts !== true)
        }

        Repeater {
          model: root.ready ? root.service.takenBinds : []
          Caption {
            required property var modelData
            text: modelData.unknown
              ? modelData.keys + " isn't bound: Stage Control couldn't read Hyprland's bindings to check that it's free."
              : modelData.keys + " is already " + (modelData.usedBy ? "used for “" + modelData.usedBy + "”" : "taken") + ", so Stage Control didn't bind it."
            color: Color.urgent
            opacity: 1
          }
        }

        SectionLabel { text: "From a terminal or your own bindings" }
        Caption {
          text: "omarchy-shell stage-control toggle      the stage\n"
            + "omarchy-shell stage-control expose      application windows\n"
            + "omarchy-shell stage-control exposeApp firefox\n"
            + "omarchy-shell stage-control settings    these settings"
          font.family: "monospace"
        }
      }

      // ---- Hot corners
      Column {
        visible: root.page === "corners"
        width: parent.width
        spacing: 12

        Caption {
          text: "Push the pointer into a corner of the screen to start an action. A corner with an action takes clicks on its last two pixels, so leave corners you click in (like the Omarchy menu, top left) empty."
        }

        Item {
          width: parent.width
          height: 260

          // The screen.
          Rectangle {
            id: screenShape
            anchors.centerIn: parent
            width: 240
            height: 150
            radius: 10
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.25)
            ClippingRectangle {
              anchors.fill: parent
              anchors.margins: 6
              radius: 6
              Image {
                anchors.fill: parent
                source: root.ready ? root.service.wallpaperUrl : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 480
                asynchronous: true
              }
            }
          }

          Repeater {
            model: [
              { key: "cornerTopLeft", top: true, left: true },
              { key: "cornerTopRight", top: true, left: false },
              { key: "cornerBottomLeft", top: false, left: true },
              { key: "cornerBottomRight", top: false, left: false }
            ]
            Dropdown {
              required property var modelData
              width: 200
              showLabel: false
              options: root.cornerActions
              value: root.settings[modelData.key] || "none"
              x: modelData.left ? Math.max(0, screenShape.x - width + 40) : Math.min(parent.width - width, screenShape.x + screenShape.width - 40)
              y: modelData.top ? 0 : parent.height - rowHeight
              onChanged: function(v) { root.set(modelData.key, v) }
            }
          }
        }
      }

      // ---- Appearance
      Column {
        visible: root.page === "look"
        width: parent.width
        spacing: 10

        SectionLabel { text: "Glass"; topPadding: 0 }
        ButtonGroup {
          options: [{ value: "liquid", label: "Liquid" }, { value: "frosted", label: "Frosted" }, { value: "solid", label: "Solid" }]
          value: root.settings.glass || "liquid"
          onChanged: function(v) { root.set("glass", v) }
        }
        Caption { text: "Liquid bends the wallpaper at the edges like macOS Tahoe; Frosted blurs more; Solid is plain and lightest on the GPU." }

        SectionLabel { text: "Background" }
        ButtonGroup {
          options: [{ value: "blur", label: "Blurred wallpaper" }, { value: "dim", label: "Dimmed wallpaper" }]
          value: root.settings.background || "blur"
          onChanged: function(v) { root.set("background", v) }
        }
        SliderRow { key: "dim"; label: "Darken the wallpaper"; bounds: [0, 80] }

        SectionLabel { text: "Highlight color" }
        Flow {
          width: parent.width
          spacing: 10
          Repeater {
            model: root.highlightChoices
            Column {
              required property var modelData
              spacing: 4
              readonly property bool chosen: (root.settings.highlight || "accent") === modelData.value
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 26
                height: 26
                radius: 13
                color: parent.modelData.color
                border.width: parent.chosen ? 3 : 1
                border.color: parent.chosen ? Color.foreground : Qt.rgba(0, 0, 0, 0.3)
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.set("highlight", parent.parent.modelData.value)
                }
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.modelData.label
                textFormat: Text.PlainText
                color: Color.foreground
                opacity: parent.chosen ? 1 : 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        SectionLabel { text: "Motion" }
        SliderRow { key: "speed"; label: "Animation speed"; bounds: [50, 200] }
        Toggle {
          width: parent.width
          label: "Reduce motion"
          description: "The stage fades in and out instead of flying the windows around."
          checked: root.settings.reduceMotion === true
          onClicked: root.set("reduceMotion", root.settings.reduceMotion !== true)
        }
      }
    }
  }

  ConfirmDialog {
    anchors.fill: parent
    z: 10
    opened: root.resetConfirmOpen
    message: "Reset Stage Control to its default settings?"
    confirmText: "Reset"
    onCanceled: root.resetConfirmOpen = false
    onConfirmed: {
      root.resetConfirmOpen = false
      if (root.ready) root.service.resetSettings()
    }
  }
}
