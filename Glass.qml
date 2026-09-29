import QtQuick
import QtQuick.Effects

// A Liquid Glass pane. Given the layer behind it (`backdrop`, a texture that
// covers `backdropSpace`), it refracts that layer: frosted, bent inward at the
// rim like a thick lens, with a specular rim lit from the top left
// (shaders/glass.frag). Without a backdrop, with the "solid" style, or if the
// shader can't load, it draws a flat translucent pane with the same rim.
// Content goes inside, as children.
//
// style: "liquid" (clear glass), "frosted" (more blur and tint), or "solid".
Item {
  id: glass

  property real radius: height / 2
  property string style: "liquid"
  property bool dark: true
  property bool shadow: true
  property bool hovered: false
  property bool pressed: false
  property bool selected: false
  property color selectedColor: "#0a84ff"
  // How much of selectedColor fills a selected pane (a solid selection is
  // 0.78; a tint that keeps the glass is around 0.25).
  property real selectedStrength: 0.78
  property color outlineColor: "transparent"
  property real outlineWidth: 0
  property Item backdrop: null
  property Item backdropSpace: null

  readonly property bool refracting: style !== "solid" && !!backdrop && !!backdropSpace && lens.status !== ShaderEffect.Error

  default property alias content: inner.data

  RectangularShadow {
    anchors.fill: parent
    radius: glass.radius
    offset: Qt.vector2d(0, 4)
    blur: 18
    spread: -2
    color: Qt.rgba(0, 0, 0, glass.style === "solid" ? 0.35 : 0.24)
    visible: glass.shadow && glass.opacity > 0
  }

  ShaderEffect {
    id: lens
    anchors.fill: parent
    visible: glass.refracting

    property var backdrop: glass.backdrop
    property size itemSize: Qt.size(width, height)
    property real radius: glass.radius
    property real bevel: Math.max(4, Math.min(width, height) * 0.34)
    property real refraction: glass.style === "liquid" ? Math.min(12, Math.min(width, height) * 0.24) : 4
    property real frost: glass.style === "liquid" ? 1.6 : 3.2
    property real rim: glass.style === "liquid" ? 1.0 : 0.7
    property real flip: 0
    property vector4d area: Qt.vector4d(0, 0, 1, 1)
    property vector4d tint: glass.dark
      ? Qt.vector4d(0.05, 0.05, 0.07, glass.style === "liquid" ? 0.32 : 0.46)
      : Qt.vector4d(1, 1, 1, glass.style === "liquid" ? 0.30 : 0.50)
    property vector4d fill: glass.selected ? Qt.vector4d(glass.selectedColor.r, glass.selectedColor.g, glass.selectedColor.b, glass.selectedStrength)
      : glass.pressed ? Qt.vector4d(0, 0, 0, 0.16)
      : glass.hovered ? Qt.vector4d(1, 1, 1, 0.12)
      : Qt.vector4d(0, 0, 0, 0)

    fragmentShader: Qt.resolvedUrl("shaders/glass.frag.qsb")
  }

  // Where the pane sits over the backdrop, followed every frame while it
  // shows (panes ride on animated parents).
  FrameAnimation {
    running: glass.refracting && glass.visible && glass.opacity > 0
    onTriggered: glass.updateArea()
  }

  function updateArea() {
    if (!backdropSpace) return
    var a = glass.mapToItem(backdropSpace, 0, 0)
    var b = glass.mapToItem(backdropSpace, glass.width, glass.height)
    var w = Math.max(1, backdropSpace.width)
    var h = Math.max(1, backdropSpace.height)
    var next = Qt.vector4d(a.x / w, a.y / h, (b.x - a.x) / w, (b.y - a.y) / h)
    var now = lens.area
    if (Math.abs(next.x - now.x) + Math.abs(next.y - now.y) + Math.abs(next.z - now.z) + Math.abs(next.w - now.w) > 0.00001)
      lens.area = next
  }

  // The drawn pane, for when there is nothing to refract.
  Item {
    id: drawn
    anchors.fill: parent
    visible: !glass.refracting

    readonly property real bodyAlpha: glass.style === "solid" ? 0.92 : glass.style === "frosted" ? 0.30 : 0.18
    readonly property color baseColor: glass.dark ? Qt.rgba(0.14, 0.14, 0.16, 1) : Qt.rgba(0.97, 0.97, 0.98, 1)
    readonly property real lift: glass.pressed ? -0.04 : glass.hovered ? 0.06 : 0

    Rectangle {
      anchors.fill: parent
      radius: glass.radius
      gradient: Gradient {
        GradientStop {
          position: 0
          color: glass.selected ? Qt.rgba(glass.selectedColor.r, glass.selectedColor.g, glass.selectedColor.b, Math.min(1, glass.selectedStrength + 0.07))
            : glass.dark ? Qt.rgba(0.27, 0.27, 0.30, Math.min(1, drawn.bodyAlpha + drawn.lift))
            : Qt.rgba(1, 1, 1, Math.min(1, drawn.bodyAlpha + 0.30 + drawn.lift))
        }
        GradientStop {
          position: 1
          color: glass.selected ? Qt.rgba(glass.selectedColor.r, glass.selectedColor.g, glass.selectedColor.b, glass.selectedStrength)
            : Qt.rgba(drawn.baseColor.r, drawn.baseColor.g, drawn.baseColor.b,
                      Math.min(1, drawn.bodyAlpha + 0.06 + drawn.lift))
        }
      }
    }

    // Rim: a hairline, brighter across the top half.
    Rectangle {
      anchors.fill: parent
      radius: glass.radius
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, glass.style === "solid" ? 0.10 : 0.16)
    }
    Item {
      anchors.left: parent.left
      anchors.right: parent.right
      height: Math.max(glass.radius, parent.height * 0.5)
      clip: true
      Rectangle {
        width: glass.width
        height: glass.height
        radius: glass.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, glass.style === "solid" ? 0.18 : 0.34)
      }
    }
  }

  // Selection ring, drawn over the glass.
  Rectangle {
    anchors.fill: parent
    radius: glass.radius
    color: "transparent"
    border.width: glass.outlineWidth
    border.color: glass.outlineColor
    visible: glass.outlineWidth > 0
  }

  Item {
    id: inner
    anchors.fill: parent
  }
}
