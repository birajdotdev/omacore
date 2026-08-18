import QtQuick
import qs.Commons

// Drawn rather than shipped as an SVG: at bar size the stems are lost to rasterisation.
Item {
  id: root

  property real iconSize: 16
  property color color: Color.foreground

  readonly property real headSize: iconSize * 0.5
  readonly property real stemWidth: iconSize * 0.22
  readonly property real stemHeight: iconSize * 0.34
  readonly property real budSpacing: iconSize * 0.16

  // Two buds side by side are wider than they are tall, so the implicit
  // size follows the actual drawn content rather than a square iconSize box
  // — otherwise a Loader with no anchors.fill (e.g. PanelHero) sizes the
  // icon too small and crops it.
  implicitWidth: headSize * 2 + budSpacing
  implicitHeight: headSize + stemHeight
  width: implicitWidth
  height: implicitHeight

  Row {
    anchors.centerIn: parent
    spacing: root.budSpacing

    Bud { head: root.headSize; stemW: root.stemWidth; stemH: root.stemHeight; ink: root.color }
    Bud { head: root.headSize; stemW: root.stemWidth; stemH: root.stemHeight; ink: root.color }
  }

  // A stubbier capsule than a stemmed earbud, closer to Soundcore's own silhouette.
  component Bud: Item {
    id: bud
    property real head: 0
    property real stemW: 0
    property real stemH: 0
    property color ink: Color.foreground

    width: head
    height: head + stemH

    Rectangle {
      width: bud.head
      height: bud.head
      radius: width * 0.42
      color: bud.ink
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: bud.head * 0.78
      width: bud.stemW
      height: bud.stemH
      radius: width / 2
      color: bud.ink
    }
  }
}
