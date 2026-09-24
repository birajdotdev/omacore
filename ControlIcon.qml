import QtQuick
import qs.Commons

// Small original line icons; colors follow the active Omarchy theme.
Canvas {
  id: icon
  property string kind: "normal"
  property color ink: Color.foreground
  implicitWidth: Style.space(26)
  implicitHeight: Style.space(26)
  onKindChanged: requestPaint()
  onInkChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var c = getContext("2d")
    c.reset()
    c.scale(width / 28, height / 28)
    c.strokeStyle = ink
    c.fillStyle = ink
    c.lineWidth = 1.8
    c.lineCap = "round"
    c.lineJoin = "round"
    function line(x, y, x2, y2) { c.beginPath(); c.moveTo(x,y); c.lineTo(x2,y2); c.stroke() }
    if (kind === "case") {
      c.beginPath(); c.roundedRect(3, 7, 22, 15, 5, 5); c.stroke()
      line(4,12,24,12)
      line(12,17,16,17)
    } else if (kind === "left" || kind === "right") {
      c.beginPath(); c.arc(14,14,11,0,Math.PI*2); c.stroke()
      c.font = "16px sans-serif"
      c.textAlign = "center"
      c.textBaseline = "middle"
      c.fillText(kind === "left" ? "L" : "R",14,15)
    } else if (kind === "ambient") {
      for (var i=0;i<5;i++) {
        var h = [5,13,22,13,5][i]
        c.lineWidth = 2.3
        line(4+i*5,14-h/2,4+i*5,14+h/2)
      }
    } else {
      // Soundcore's person silhouette with a solid or dotted surrounding arc.
      c.beginPath(); c.arc(14,13,4.5,0,Math.PI*2); c.fill()
      c.beginPath(); c.moveTo(6,25); c.quadraticCurveTo(6,19,10,19)
      c.lineTo(18,19); c.quadraticCurveTo(22,19,22,25); c.closePath(); c.fill()
      c.lineWidth = 2.4
      if (kind === "transparency") {
        // Flat ends leave real gaps even at small desktop sizes.
        c.lineCap = "butt"
        c.lineWidth = 2.8
        for (var j=0;j<10;j++) {
          var start = Math.PI*0.83 + j*Math.PI*1.34/10
          c.beginPath(); c.arc(14,13,10,start,start+0.24); c.stroke()
        }
      } else {
        // Normal keeps the person opaque but fades its surrounding arc,
        // including when selected, as in the Soundcore app.
        c.globalAlpha = kind === "normal" ? 0.28 : 1.0
        c.beginPath(); c.arc(14,13,10,Math.PI*0.83,Math.PI*2.17); c.stroke()
        c.globalAlpha = 1.0
      }
    }
  }
}
